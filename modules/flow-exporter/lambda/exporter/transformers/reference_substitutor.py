# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Reference substitutor for Amazon Connect resource exports.

Transforms ARNs and IDs in resource content to template variables
for cross-environment portability.

Uses Terraform-safe Base64 encoding: + -> -, / -> _, remove = padding.
"""

import base64
import json
import re
import logging

import boto3


logger = logging.getLogger(__name__)


class ReferenceSubstitutor:
    """Substitute ARNs/IDs with portable template variables."""

    _PREFIXED_RESOURCE_TYPES = {
        "contact_flow",
        "flow_module",
        "view",
    }

    _SKIP_NAME_SUBSTITUTION_TYPES = {
        "view",
    }

    def __init__(self, connect_client, instance_id, name_prefix=""):
        self._connect = connect_client
        self._instance_id = instance_id
        self._name_prefix = name_prefix or ""
        self._ref_cache = {}       # arn/id -> template var
        self._name_cache = {}      # display name -> display placeholder
        self._ambiguous_names = set() # display names that are not unique across resources.
        self._name_owner = {}       # display name -> resource_type that owns it (if unique)
        self._id_to_name = {}      # resource_type -> {id: name}
        self._id_to_arn = {}       # resource_type -> {id: arn}
        self._initialized = False

    # ------------------------------------------------------------------
    # Name normalization
    # ------------------------------------------------------------------

    def _canonical_name(self, resource_type, name):
        """Return the bare (prefix-stripped) name for prefixed resource types.

        Prefix stripping applies only to resource types listed in
        _PREFIXED_RESOURCE_TYPES. For all other types (queue, lambda, etc.)
        the live name is already canonical and returned unchanged.
        """
        if (
            self._name_prefix
            and resource_type in self._PREFIXED_RESOURCE_TYPES
            and name.startswith(self._name_prefix)
        ):

            return name[len(self._name_prefix):]
        return name

    # ------------------------------------------------------------------
    # Encoding helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _encode_name(name):
        """Encode name to Terraform-safe Base64."""
        encoded = base64.b64encode(name.encode("utf-8")).decode("ascii")
        return encoded.replace("+", "-").replace("/", "_").rstrip("=")

    # ------------------------------------------------------------------
    # Resource registration
    # ------------------------------------------------------------------

    def _register(self, resource_type, rid, name, arn=None):
        canonical = self._canonical_name(resource_type, name)
        encoded = self._encode_name(canonical)
        tpl = "${%s_%s}" % (resource_type, encoded)
        if arn:
            self._ref_cache[arn] = tpl
            self._id_to_arn.setdefault(resource_type, {})[rid] = arn
        self._ref_cache[rid] = tpl
        self._id_to_name.setdefault(resource_type, {})[rid] = canonical

    # Both the live name and the canonical name should resolve to the
    # same display placeholder so that display names embedded in
    # cross-resource Metadata blocks (e.g. "Transfer to <flow name>")
    # substitute correctly whether they carry the prefix or not.

        display_tpl = "${display_%s_%s}" % (resource_type, encoded)
        self._register_display_name(resource_type, name, display_tpl)
        if canonical != name:
            self._name_cache[canonical] = display_tpl
            self._register_display_name(resource_type, canonical, display_tpl)

    def _register_display_name(self, resource_type, name, display_tpl):
        """Register a name → display placeholder mapping, detecting collisions.

        If a different resource type previously registered the same name,
        the name is marked ambiguous and removed from _name_cache. Subsequent
        lookups will miss, and _substitute_value() will leave the literal
        name in place — which is always a valid, env-portable substitution
        for display / text fields (Connect GUI renders the literal name
        correctly in every environment).

        This is resource-type-agnostic: it catches collisions between ANY
        combination of types (queue ↔ routing_profile, view ↔ data_table,
        HOOP ↔ routing_profile, flow_module ↔ contact_flow, etc.).
        """
        if name in self._ambiguous_names:
            # Already marked ambiguous by an earlier collision; nothing more
            # to do — _name_cache is already cleared for this name.
            return

        existing = self._name_cache.get(name)
        if existing is not None and existing != display_tpl:
            # Different type is registering the same display name.
            prior_type = self._name_owner.get(name, "unknown")
            logger.warning(
                "Name collision: '%s' is registered as both %s and %s; "
                "display-name substitution disabled for this name. The "
                "literal name will be emitted in Metadata text/displayName "
                "fields instead. (id/ARN substitution is unaffected.)",
                name, prior_type, resource_type,
            )
            # Drop the existing entry and mark ambiguous so we never pick
            # either type's placeholder for this name.
            self._name_cache.pop(name, None)

            self._name_owner.pop(name, None)
            self._ambiguous_names.add(name)
            return
        self._name_cache[name] = display_tpl
        self._name_owner[name] = resource_type

    # ------------------------------------------------------------------
    # Build reference mapping (lazy, called once)
    # ------------------------------------------------------------------

    def _build_mapping(self):
        if self._initialized:
            return
        logger.info("Building reference mapping for instance '%s'", self._instance_id)

        self._build_instance_mapping()
        self._build_paginated_mapping("queue", "list_queues", "QueueSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_paginated_mapping("contact_flow", "list_contact_flows", "ContactFlowSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_paginated_mapping("flow_module", "list_contact_flow_modules", "ContactFlowModulesSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_paginated_mapping("hours_of_operation", "list_hours_of_operations", "HoursOfOperationSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_paginated_mapping("routing_profile", "list_routing_profiles", "RoutingProfileSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_prompt_mapping()
        self._build_lambda_mapping()
        self._build_data_table_mapping()
        self._build_lex_bot_mapping()
        self._build_voice_connector_mapping()
        self._build_paginated_mapping("view", "list_views", "ViewsSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")
        self._build_paginated_mapping("quick_connect", "list_quick_connects", "QuickConnectSummaryList",
                                      id_key="Id", name_key="Name", arn_key="Arn")

        self._initialized = True
        logger.info("Built reference mapping with %d entries", len(self._ref_cache))

    def _build_instance_mapping(self):
        try:
            resp = self._connect.describe_instance(InstanceId=self._instance_id)
            arn = resp.get("Instance", {}).get("Arn")
            if arn:
                self._ref_cache[arn] = "${connect_instance_arn}"
                self._ref_cache[self._instance_id] = "${connect_instance_arn}"
        except Exception as e:
            logger.warning("Failed to describe instance '%s': %s", self._instance_id, e)

    def _build_paginated_mapping(self, resource_type, api_method, list_key,
                                  id_key="Id", name_key="Name", arn_key="Arn"):
        self._id_to_name.setdefault(resource_type, {})
        self._id_to_arn.setdefault(resource_type, {})
        try:
            paginator = self._connect.get_paginator(api_method)
            for page in paginator.paginate(InstanceId=self._instance_id):
                for item in page.get(list_key, []):
                    rid = item.get(id_key)
                    name = item.get(name_key)
                    if rid and name:
                        self._register(resource_type, rid, name, item.get(arn_key))
        except Exception as e:
            logger.warning("Failed to list %s: %s", resource_type, e)

    def _build_prompt_mapping(self):
        """Register custom prompts only (skip built-in .wav/.mp3 prompts)."""
        self._id_to_name.setdefault("prompt", {})
        self._id_to_arn.setdefault("prompt", {})
        try:
            paginator = self._connect.get_paginator("list_prompts")
            for page in paginator.paginate(InstanceId=self._instance_id):
                for prompt in page.get("PromptSummaryList", []):
                    pid, name, arn = prompt.get("Id"), prompt.get("Name"), prompt.get("Arn")
                    if not pid or not name:
                        continue
                    if arn:
                        self._id_to_arn["prompt"][pid] = arn
                    self._id_to_name["prompt"][pid] = name
                    is_builtin = bool(re.search(r"\.(wav|mp3)$", name, re.IGNORECASE))
                    if not is_builtin:
                        self._register("prompt", pid, name, arn)
        except Exception as e:
            logger.warning("Failed to list prompts: %s", e)

    def _build_lambda_mapping(self):
        self._id_to_name.setdefault("lambda", {})
        self._id_to_arn.setdefault("lambda", {})
        try:
            resp = self._connect.list_lambda_functions(InstanceId=self._instance_id)
            for fn_arn in resp.get("LambdaFunctions", []):
                m = re.search(r"function:([a-zA-Z0-9_-]+)", fn_arn)
                if m:
                    name = m.group(1)
                    encoded = self._encode_name(name)
                    self._ref_cache[fn_arn] = "${lambda_%s}" % encoded
                    self._id_to_arn["lambda"][name] = fn_arn
                    self._id_to_name["lambda"][name] = name
                    self._name_cache[name] = "${display_lambda_%s}" % encoded
        except Exception as e:
            logger.warning("Failed to list Lambda functions: %s", e)

    def _build_data_table_mapping(self):
        """Register data tables so both ARN and bare DataTableId are substituted.

        Uses list_data_tables (no paginator available yet) with manual
        NextToken pagination. Each table's Id (UUID) and Arn are both
        cached via _register(), keyed by the table Name — matching the
        Terraform-side encoding in data_table_registry_map.
        """
        self._id_to_name.setdefault("data_table", {})
        self._id_to_arn.setdefault("data_table", {})
        self._id_to_name.setdefault("data_table_attribute", {})
        self._id_to_arn.setdefault("data_table_attribute", {})
        table_ids = []

        try:

            kwargs = {"InstanceId": self._instance_id, "MaxResults": 100}

            while True:
                resp = self._connect.list_data_tables(**kwargs)
                for item in resp.get("DataTableSummaryList", []):
                    rid = item.get("Id")
                    name = item.get("Name")
                    arn = item.get("Arn")

                    if rid and name:
                        self._register("data_table", rid, name, arn)
                        table_ids.append((rid, name))
                        logger.info("Registered data table '%s' with id '%s'", name, rid)

                next_token = resp.get("NextToken")
                if not next_token:
                    break

                kwargs["NextToken"] = next_token

            logger.info(
                "Data table mapping built with %d entries",
                len(self._id_to_name.get("data_table", {})),
            )

        except AttributeError:
            logger.error(
                "list_data_tables not available in this boto3 version. "
                "Runtime boto3 needs >=1.35.0 for Connect DataTables API support."
            )
        except Exception as e:
            logger.error(
                "Failed to list data tables: %s (type: %s)", e, type(e).__name__
            )
        # Enumerate attributes for each data table
        attr_count = 0
        for table_id, table_name in table_ids:
            try:
                attr_kwargs = {"InstanceId": self._instance_id, "DataTableId": table_id, "MaxResults": 100}
                while True:
                    dt_resp = self._connect.list_data_table_attributes(**attr_kwargs)
                    for attr in dt_resp.get("Attributes", []):
                        attr_id = attr.get("AttributeId")
                        attr_name = attr.get("Name")
                        if attr_id and attr_name:
                            composite_name = f"{table_name}_{attr_name}"
                            encoded = self._encode_name(composite_name)
                            tpl = "${data_table_attribute_%s}" % encoded
                            self._ref_cache[attr_id] = tpl
                            self._id_to_name["data_table_attribute"][attr_id] = composite_name
                            attr_count += 1
                            logger.debug("Registered data table attribute '%s.%s' (id=%s)",
                                         table_name, attr_name, attr_id)
                    next_token = dt_resp.get("NextToken")
                    if not next_token:
                        break
                    attr_kwargs["NextToken"] = next_token
            except Exception as e:
                logger.warning("Failed to list attributes for data table '%s' (id=%s): %s",
                               table_name, table_id, e)
        logger.info("Data table attribute mapping built with %d entries", attr_count)

    def _build_lex_bot_mapping(self):
        """Register Lex V2 bot aliases as portable ${lex_bot_<base64(name)>} placeholders.

        The Connect ListBots API surfaces only the V2 alias ARN, but the
        bot **name** is what's stable across environments — IDs, alias
        IDs and account IDs all differ per env. So for every bot
        association we resolve the alias ARN back to its bot name via
        the lexv2-models DescribeBot API, and base64-encode that name
        as the placeholder key.

        Both the alias ARN and a few canonical sub-strings (bot id,
        alias id, "<bot_id>:<alias_id>") are registered so any flow
        node format the Connect designer might emit substitutes
        correctly.
        """
        self._id_to_name.setdefault("lex_bot", {})
        self._id_to_arn.setdefault("lex_bot", {})

        # Lazily build a lexv2-models client. Failure is non-fatal —
        # we fall back to the live alias ARN parser below.
        lexv2_client = None
        try:
            lexv2_client = boto3.client("lexv2-models")
        except Exception as e:
            logger.warning("Failed to create lexv2-models client: %s", e)

        # Cache bot_id -> bot_name lookups so repeated DescribeBot calls
        # are avoided when multiple flows reference the same bot.
        bot_id_to_name = {}

        def _resolve_bot_name(bot_id, alias_arn):
            if not bot_id:
                return None
            if bot_id in bot_id_to_name:
                return bot_id_to_name[bot_id]
            if not lexv2_client:
                return None
            try:
                resp = lexv2_client.describe_bot(botId=bot_id)
                name = resp.get("botName")
                if name:
                    bot_id_to_name[bot_id] = name
                    return name
            except Exception as e:
                logger.warning(
                    "Failed to describe Lex V2 bot id=%s (alias %s): %s",
                    bot_id, alias_arn, e,
                )
            return None

        # ListBots V2 returns alias ARNs of bots associated with the
        # Connect instance. ListBots is NextToken-paginated (max 25 per
        # page); we use a manual NextToken loop — same pattern as
        # _build_data_table_mapping — so we don't depend on a registered
        # boto3 paginator being present.
        try:
            kwargs = {"InstanceId": self._instance_id, "LexVersion": "V2"}
            while True:
                resp = self._connect.list_bots(**kwargs)
                for bot_cfg in resp.get("LexBots", []):
                    v2 = bot_cfg.get("LexV2Bot", {})
                    alias_arn = v2.get("AliasArn")
                    if not alias_arn:
                        continue

                    # Alias ARN format:
                    #   arn:aws:lex:<region>:<account>:bot-alias/<bot_id>/<alias_id>
                    m = re.match(
                        r"arn:aws:lex:[a-z0-9-]+:\d{12}:bot-alias/([0-9a-zA-Z]+)/([0-9a-zA-Z]+)",
                        alias_arn,
                    )
                    bot_id = m.group(1) if m else None
                    alias_id = m.group(2) if m else None

                    bot_name = _resolve_bot_name(bot_id, alias_arn)
                    if not bot_name:
                        # Couldn't resolve the env-stable name — skip
                        # registration so we leave the literal alias
                        # ARN in place rather than emit a per-env
                        # placeholder.
                        logger.warning(
                            "Skipping Lex bot registration for alias %s — "
                            "bot name could not be resolved.",
                            alias_arn,
                        )
                        continue

                    encoded = self._encode_name(bot_name)
                    placeholder = "${lex_bot_%s}" % encoded
                    display_placeholder = "${display_lex_bot_%s}" % encoded

                    # Register every sub-form a flow JSON might carry.
                    self._ref_cache[alias_arn] = placeholder
                    if bot_id:
                        self._ref_cache[bot_id] = placeholder
                    if alias_id:
                        self._ref_cache[alias_id] = placeholder
                    if bot_id and alias_id:
                        self._ref_cache[f"{bot_id}:{alias_id}"] = placeholder

                    # Keyed indexes (mirror voice_connector / queue
                    # registration) so registry_writer emits the
                    # friendly bot name and alias ARN.
                    if bot_id:
                        self._id_to_arn["lex_bot"][bot_id] = alias_arn
                        self._id_to_name["lex_bot"][bot_id] = bot_name

                    # Both the live name (bot_name) and a "Lex Bot
                    # Alias" display string flow designers sometimes
                    # emit should resolve to the same display
                    # placeholder. Guarded by collision detection.
                    self._register_display_name("lex_bot", bot_name, display_placeholder)

                next_token = resp.get("NextToken")
                if not next_token:
                    break
                kwargs["NextToken"] = next_token
        except Exception as e:
            logger.warning("Failed to list V2 Lex bots: %s", e)

    def _build_voice_connector_mapping(self):
        """Register Chime Voice Connectors associated with the Connect instance.

        Voice Connectors are referenced in contact flows via their full Chime ARN
        (``arn:aws:chime:<region>:<account>:vc/<vc-id>``). Chime VC IDs differ per
        environment, but the VC **name** (for example ``anycompany-ext-voice-connector``)
        is managed in Terraform and consistent across environments. We register
        each VC ARN to a placeholder derived from the name, so the same ``.tpl``
        renders correctly in every environment.

        Discovery source: ``list_integration_associations`` on the Connect
        instance filtered to CALL_TRANSFER_CONNECTOR integrations. Each
        association's ``IntegrationArn`` is a Chime VC ARN. The VC name comes
        from ``list_voice_connectors`` on the Chime SDK Voice client.
        """
        self._id_to_name.setdefault("voice_connector", {})
        self._id_to_arn.setdefault("voice_connector", {})

        # Lazily create Chime SDK Voice client; boto3 service name is
        # "chime-sdk-voice" (previously "chime").
        try:
            chime_client = boto3.client("chime-sdk-voice")
        except Exception as e:
            logger.warning("Failed to create chime-sdk-voice client: %s", e)
            return

        # Build map of VC id -> name from Chime (no paginator available)
        vc_id_to_name = {}
        try:
            kwargs = {}
            while True:
                resp = chime_client.list_voice_connectors(**kwargs)
                for vc in resp.get("VoiceConnectors", []):
                    vc_id = vc.get("VoiceConnectorId")
                    vc_name = vc.get("Name")
                    if vc_id and vc_name:
                        vc_id_to_name[vc_id] = vc_name
                next_token = resp.get("NextToken")
                if not next_token:
                    break
                kwargs["NextToken"] = next_token
        except Exception as e:
            logger.warning("Failed to list Chime Voice Connectors: %s", e)
            return

        # Register only VCs associated with this Connect instance
        try:
            paginator = self._connect.get_paginator("list_integration_associations")
            for page in paginator.paginate(
                InstanceId=self._instance_id,
                IntegrationType="CALL_TRANSFER_CONNECTOR",
            ):
                for assoc in page.get("IntegrationAssociationSummaryList", []):
                    arn = assoc.get("IntegrationArn")
                    if not arn:
                        continue
                    m = re.match(
                        r"arn:aws:chime:[a-z0-9-]+:\d{12}:vc/([a-zA-Z0-9]+)", arn
                    )
                    if not m:
                        continue
                    vc_id = m.group(1)
                    vc_name = vc_id_to_name.get(vc_id)
                    if not vc_name:
                        logger.warning(
                            "Voice connector %s has no name in Chime; skipping",
                            vc_id,

                        )
                        continue
                    self._register("voice_connector", vc_id, vc_name, arn)
                    logger.info(
                        "Registered voice connector '%s' (id=%s, arn=%s)",
                        vc_name, vc_id, arn,
                    )
        except Exception as e:
            logger.warning("Failed to list integration associations: %s", e)

    # ------------------------------------------------------------------
    # Substitution logic
    # ------------------------------------------------------------------

    _SERVICE_PATTERNS = [
        (r"arn:aws:voiceid:[a-z0-9-]+:\d{12}:domain/([a-zA-Z0-9-]+)", "voiceid_domain"),
        (r"arn:aws:profile:[a-z0-9-]+:\d{12}:domains/([a-zA-Z0-9_-]+)", "customer_profiles_domain"),
        (r"arn:aws:cases:[a-z0-9-]+:\d{12}:domain/([a-zA-Z0-9-]+)", "cases_domain"),
        (r"arn:aws:wisdom:[a-z0-9-]+:\d{12}:assistant/([a-zA-Z0-9-]+)", "wisdom_assistant"),
        (r"arn:aws:qconnect:[a-z0-9-]+:\d{12}:assistant/([a-zA-Z0-9-]+)", "wisdom_assistant"),
        (r"arn:aws:connect:[a-z0-9-]+:\d{12}:instance/[a-f0-9-]+/data-table/([a-zA-Z0-9-]+)", "data_table"),
        (r"(?:arn:aws:s3:::|s3://)([a-zA-Z0-9._-]+)/(.+)", "s3_content"),
    ]

    _UUID_RE = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", re.IGNORECASE)
    _FLOW_MODULE_VERSION_RE = re.compile(
        r"^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})(:\$?[A-Za-z0-9]+)?$", re.IGNORECASE
    )

    # A Connect sub-resource ARN carrying a trailing version/alias qualifier.
    #
    # Required for the "Show View" flow block, which references its view as a
    # QUALIFIED ARN — confirmed from a real UI-authored flow export:
    #
    #   "Parameters": {
    #     "ViewResource": {
    #       "Id": "arn:aws:connect:<region>:<acct>:instance/<iid>/view/<vid>:$LATEST"
    #     },
    #     "Type": "ShowView"
    #
    # The Connect ListXxx APIs return UNQUALIFIED ARNs, so the qualified form
    # never matches _ref_cache directly. Without this the literal ARN — carrying
    # account id, region and instance id — is baked into the exported template.
    #
    # Group 1 is the unqualified ARN (the _ref_cache key); group 2 is the
    # ":<qualifier>" suffix, preserved verbatim and re-appended to the resolved
    # placeholder so the flow keeps pointing at the same version/alias.
    #
    # NOTE: the trailing qualifier is REQUIRED by this pattern, so unqualified
    # ARNs cannot match and are unaffected. Contact flow references between
    # flows are unqualified and continue to resolve via the _ref_cache hit at
    # the top of _substitute_value, exactly as before.
    _QUALIFIED_CONNECT_ARN_RE = re.compile(
        r"^(arn:aws[-a-z0-9]*:connect:[a-z0-9-]+:\d{12}:instance/[-a-zA-Z0-9]+/[a-z-]+/[-a-zA-Z0-9]+)"
        r"(:\$?[A-Za-z0-9_-]+)$",
        re.IGNORECASE,
    )

    # Flow-language fields whose values are UUIDs by design: an action's own
    # identity and the wiring between actions. They are not references to Connect
    # resources, so failing to resolve them is expected, not a problem.
    #
    # Without this, every action in every flow logged a warning — about 20 lines
    # per export — and that noise buried the warning that matters: a reference to
    # a resource Terraform does not manage, which is the one failure the
    # placeholder scheme cannot recover from.
    _STRUCTURAL_KEYS = frozenset({
        "Identifier", "NextAction", "StartAction", "StartFlowAction",
    })

    def _looks_like_arn_or_id(self, value):
        return value.startswith("arn:aws:") or bool(self._UUID_RE.match(value))

    def _substitute_value(self, value, resource_type=None, key=None):
        if value in self._ref_cache:
            return self._ref_cache[value]
        if (
            resource_type not in self._SKIP_NAME_SUBSTITUTION_TYPES
            and value in self._name_cache
        ):
            return self._name_cache[value]

        # Flow module ID with version suffix (e.g. "uuid:$LATEST")
        m = self._FLOW_MODULE_VERSION_RE.match(value)
        if m:
            base_id, version_suffix = m.group(1), m.group(2) or ""
            if base_id in self._ref_cache:
                return self._ref_cache[base_id] + version_suffix

        # Connect sub-resource ARN with a version/alias qualifier — primarily
        # the "Show View" block's ViewResource.Id ("<view-arn>:$LATEST").
        # Strip the qualifier, resolve the base ARN, re-append the qualifier.
        # See _QUALIFIED_CONNECT_ARN_RE for why this is required.
        qm = self._QUALIFIED_CONNECT_ARN_RE.match(value)
        if qm:
            base_arn, qualifier = qm.group(1), qm.group(2)
            if base_arn in self._ref_cache:
                return self._ref_cache[base_arn] + qualifier

        # Lambda ARN fallback
        lm = re.match(r"arn:aws:lambda:[a-z0-9-]+:\d{12}:function:([a-zA-Z0-9_-]+)", value)
        if lm:
            encoded = self._encode_name(lm.group(1))
            tpl = "${lambda_%s}" % encoded
            self._ref_cache[value] = tpl
            return tpl

        # Lex bot ARN fallback (V2 only).
        # The exporter standardizes on Lex V2. V2 alias ARNs embed an
        # env-specific bot id and alias id, so we deliberately do NOT
        # fabricate a placeholder from them. Anything reaching here that
        # wasn't already pre-registered by _build_lex_bot_mapping (which
        # keys on the env-stable bot **name** resolved via DescribeBot)
        # means the bot name could not be resolved at discovery time —
        # leave the literal ARN in place so the engineer sees it and can
        # re-deploy after fixing IAM / lexv2 reachability.
        #
        # No V1 handling: V1 bots are not provisioned or discovered, and
        # there is no Terraform-side lex_bot_v1 registry map. Emitting a
        # V1 placeholder here would produce an unresolvable ${lex_bot_*}
        # token that breaks templatefile() at apply time, so V1 ARNs (if
        # any ever appear) are intentionally left untouched.
        if re.match(
            r"arn:aws:lex:[a-z0-9-]+:\d{12}:bot-alias/[0-9a-zA-Z]+/[0-9a-zA-Z]+",
            value,
        ):
            logger.warning(
                "Lex V2 alias ARN %s was not pre-registered — leaving "
                "literal ARN in template (placeholder substitution "
                "skipped to avoid encoding env-specific bot/alias ids).",
                value,
            )
            return value

        # Other AWS service ARNs
        for pattern, rtype in self._SERVICE_PATTERNS:
            sm = re.match(pattern, value)
            if sm:
                if rtype == "s3_content":
                    identifier = f"{sm.group(1)}/{sm.group(2)}"
                else:
                    identifier = sm.group(1)
                encoded = self._encode_name(identifier)
                tpl = "${%s_%s}" % (rtype, encoded)
                self._ref_cache[value] = tpl
                return tpl

        if self._looks_like_arn_or_id(value):
            if key in self._STRUCTURAL_KEYS:
                logger.debug("Structural identifier left as-is: %s=%s", key, value)
            else:
                logger.warning("Unresolvable reference found, preserving original: %s", value)
        return value

    def _transform_value(self, value, resource_type=None, key=None):
        if isinstance(value, str):
            # Try to detect stringified JSON containing references
            # (e.g. view Template field is a JSON string with embedded UUIDs)
            if value.startswith("{") or value.startswith("["):
                try:
                    parsed = json.loads(value)
                    transformed = self._transform_value(parsed, resource_type, key)
                    if transformed != parsed:
                        return transformed
                except (json.JSONDecodeError, TypeError):
                    pass
            return self._substitute_value(value, resource_type, key)
        if isinstance(value, list):
            return [self._transform_value(item, resource_type, key) for item in value]
        if isinstance(value, dict):
            return {k: self._transform_value(v, resource_type, k) for k, v in value.items()}
        return value

    def transform(self, content, resource_type):
        """Transform all ARNs and IDs in content to template variables."""
        self._build_mapping()
        logger.debug("Transforming %s content with %d cached references", resource_type, len(self._ref_cache))
        if not isinstance(content, dict):
            logger.warning("Content is not a dict for %s, returning unchanged", resource_type)
            return content
        return self._transform_value(content, resource_type)

    # ------------------------------------------------------------------
    # Public accessors
    # ------------------------------------------------------------------

    def get_resource_name(self, resource_type, resource_id):
        """Return the resource name for a given type and ID, or None if unmapped."""
        return self._id_to_name.get(resource_type, {}).get(resource_id)

    def get_discovered_resources(self):
        """Return dict of resource_type -> list of {id, name, arn} for registry writing."""
        result = {}
        for rtype, id_to_name in self._id_to_name.items():
            resources = []
            id_to_arn = self._id_to_arn.get(rtype, {})
            for rid, name in id_to_name.items():
                arn = id_to_arn.get(rid)
                if arn:
                    resources.append({"id": rid, "name": name, "arn": arn})
            if resources:
                result[rtype] = resources
        return result

    def clear_cache(self):
        """Drop the cached reference and name maps, forcing a rebuild."""
        self._ref_cache.clear()
        self._name_cache.clear()
        self._ambiguous_names.clear()
        self._name_owner.clear()
        self._id_to_name.clear()
        self._id_to_arn.clear()
        self._initialized = False
