# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Placeholder resolution: turning portable templates into real Connect resources.
# =============================================================================
#
# An exported template never contains an ARN — every environment-specific
# reference is a ${<family>_<base64 name>} placeholder. This module rebuilds
# those keys from the resources Terraform manages in THIS instance and hands the
# resulting map to templatefile(), so one template deploys anywhere.
#
# The encoding itself lives in modules/placeholder-keys, which explains it and is
# the only place it is written down. Read that first.
#
# This module is called by BOTH root modules. That is the proof of portability:
# the same code renders the same template format against two different
# instances. The only difference is where the template came from — the repo, or
# the exporter.

# Keys for everything whose ID is known before any flow resource is created.
module "base_keys" {
  source = "../placeholder-keys"

  resources = {
    queue              = var.queue_ids
    hours_of_operation = var.hours_of_operation_ids
    # A flow's Data table block stores the table by ID.
    data_table = var.data_table_ids
  }

  # Contact flows and flow modules appear here but NOT in `resources`: their
  # Metadata labels are needed, while their IDs are either resolved dynamically
  # at contact time (flows) or supplied separately below (modules).
  display_names = {
    queue              = keys(var.queue_ids)
    hours_of_operation = keys(var.hours_of_operation_ids)
    data_table         = keys(var.data_table_ids)
    contact_flow       = keys(var.contact_flow_definitions)
    flow_module        = keys(var.contact_flow_module_definitions)
  }
}

# Keys for the flow modules this module just created. Kept in a SEPARATE call
# because merging them into base_keys would create a dependency cycle — see the
# comment on flow_replacement_map below.
module "flow_module_keys" {
  source = "../placeholder-keys"

  resources = {
    flow_module = local.flow_module_ids_live
  }
}

locals {
  # Flow modules referenced BY contact flows can use the live module output:
  # flows depend on modules, not the reverse, so there is no cycle.
  #
  # Merged across both ownership variants — exactly one is non-empty.
  #
  # The awscc resource exposes contact_flow_module_arn and a composite `id`, but
  # not a bare module ID — and an InvokeFlowModule block needs the bare UUID. So
  # take the last ARN segment:
  #   arn:aws:connect:<region>:<acct>:instance/<iid>/flow-module/<UUID>
  flow_module_ids_live = merge(
    { for k, v in awscc_connect_contact_flow_module.console_owned : k => regex("[^/]+$", v.contact_flow_module_arn) },
    { for k, v in awscc_connect_contact_flow_module.managed : k => regex("[^/]+$", v.contact_flow_module_arn) },
  )

  # Two maps, not one, and the difference is a dependency cycle.
  #
  # A flow module's own content cannot be rendered with a map that contains
  # flow-module IDs: the IDs come from the very resources being created, so
  # Terraform sees module -> map -> module. Modules therefore render WITHOUT the
  # flow_module_* value family, which also enforces the demo's constraint that a
  # module does not invoke another module. (The production code allows that and
  # pays for it by reading IDs from the previous apply's state.)
  #
  # Contact flows render WITH it, because modules are created first and flows
  # depend on modules rather than the reverse. No cycle in that direction.
  #
  # Note there is deliberately NO contact_flow_<b64> VALUE family in either map:
  # a flow that transfers to another flow does so via a dynamic reference read
  # from the data table at contact time. That is what removes the last cycle and
  # the need for a second apply. See the README.
  #
  # extra_replacements is merged last in both, so a caller can always override.
  module_replacement_map = merge(
    module.base_keys.placeholder_map,
    var.extra_replacements,
  )

  flow_replacement_map = merge(
    module.base_keys.placeholder_map,
    module.flow_module_keys.placeholder_map,
    var.extra_replacements,
  )

  # --- Rendering ------------------------------------------------------------
  #
  # templatefile() fails the plan if a template references a key that is not in
  # the map. That is the desired behaviour: an unresolvable reference stops the
  # pipeline instead of deploying a flow that points at nothing.

  rendered_modules = {
    for name, def in var.contact_flow_module_definitions :
    name => jsondecode(templatefile("${var.template_dir}/${def.template}", local.module_replacement_map))
  }

  rendered_flows = {
    for name, def in var.contact_flow_definitions :
    name => jsondecode(templatefile("${var.template_dir}/${def.template}", local.flow_replacement_map))
  }
}

# Who owns flow content: the console, or Terraform?
# =============================================================================
#
# This is the asymmetry the whole pattern rests on, and the two instances need
# OPPOSITE answers:
#
#   source instance  the console owns content. A designer edits a flow and
#                    re-applying Terraform must not revert them.
#   target instance  Terraform owns content. That IS promotion — a new template
#                    has to update the deployed flow.
#
# Terraform's `lifecycle` block cannot take a variable, so `ignore_changes`
# cannot be toggled by input. The only way to express both behaviours in one
# module is two resource blocks selected by an empty for_each. Everything except
# the lifecycle block is identical, so the definitions come from shared locals
# and outputs merge the two sets.
#
# Naming these "console_owned" and "managed" rather than something like "a"/"b"
# keeps `terraform state list` readable about which model applies.

locals {
  modules_console_owned = var.console_owns_content ? var.contact_flow_module_definitions : {}
  modules_managed       = var.console_owns_content ? {} : var.contact_flow_module_definitions
  flows_console_owned   = var.console_owns_content ? var.contact_flow_definitions : {}
  flows_managed         = var.console_owns_content ? {} : var.contact_flow_definitions

  # The awscc schema marks `settings` optional, but the Connect API rejects a
  # null with:
  #
  #   JSON field is missing or null for field name: settings
  #   (Service: Connect, Status Code: 400)
  #
  # So every module needs a settings document even when it takes no parameters.
  # This is the minimum the API accepts: empty parameter lists plus the two
  # transitions every module has.
  #
  # It has to be supplied on write and is never returned on read — both
  # DescribeContactFlowModule and the Cloud Control read hand back `Settings:
  # "{}"` no matter what was written. The resource below therefore ignores
  # changes to it; see the comment there.
  #
  # A module's ACTUAL declared interface — input parameters, output parameters,
  # custom branches — travels inside `Content.Settings`, which is part of the
  # template and does round-trip. This argument only exists to satisfy the API.
  #
  # A module that declares its own interface can still override this via its
  # definition, and the value is used on create.
  default_module_settings = {
    InputParameters  = []
    OutputParameters = []
    Transitions = [
      { DisplayName = "Success", ReferenceName = "Success", Description = "" },
      { DisplayName = "Error", ReferenceName = "Error", Description = "" },
    ]
  }

  module_settings = {
    for name, def in var.contact_flow_module_definitions :
    name => jsonencode(try(def.settings, null) == null ? local.default_module_settings : def.settings)
  }

  # awscc mirrors the Cloud Control schema, where tags are a set of {key, value}
  # objects rather than the map the aws provider takes.
  awscc_tags = [for k, v in var.tags : { key = k, value = v }]
}

# -----------------------------------------------------------------------------
# Flow modules, created before contact flows so their IDs can be substituted
# -----------------------------------------------------------------------------
#
# `settings` carries module input parameters, output parameters and custom
# branches. DescribeContactFlowModule does not return them, so the exporter
# cannot put them in the template — they are declared in the definition instead.

resource "awscc_connect_contact_flow_module" "console_owned" {
  for_each = local.modules_console_owned

  instance_arn = var.instance_arn
  name         = "${var.name_prefix}${each.key}"
  description  = try(each.value.description, null)
  content      = jsonencode(local.rendered_modules[each.key].Content)
  state        = try(each.value.state, "ACTIVE")
  settings     = local.module_settings[each.key]
  tags         = local.awscc_tags

  lifecycle {
    # `settings` is write-only in the Connect API: it must be supplied and is
    # always read back as "{}". Without ignoring it, every plan reports the same
    # phantom change forever and an empty plan stops meaning "no drift".
    ignore_changes = [content, settings]
  }
}

resource "awscc_connect_contact_flow_module" "managed" {
  for_each = local.modules_managed

  instance_arn = var.instance_arn
  name         = "${var.name_prefix}${each.key}"
  description  = try(each.value.description, null)
  content      = jsonencode(local.rendered_modules[each.key].Content)
  state        = try(each.value.state, "ACTIVE")
  settings     = local.module_settings[each.key]
  tags         = local.awscc_tags

  lifecycle {
    # Content is NOT ignored here — Terraform owns it, which is what promotion
    # means. Only `settings` is, and for the same write-only reason as above.
    ignore_changes = [settings]
  }
}

# -----------------------------------------------------------------------------
# Contact flows
# -----------------------------------------------------------------------------
#
# awscc, not aws, for the same reason as the flow module: the Cloud Control
# schema tracks the Connect CloudFormation resources, so newly released Connect
# features are reachable without waiting for AWS provider support. That is the
# accelerator's stated provider preference, and it keeps flows, modules and
# versions on one provider rather than splitting them across two.
#
# Two consequences to know about:
#
#   * the resource takes instance_arn, not instance_id, and exposes
#     contact_flow_arn plus a composite `id` — never a bare flow ID. Everything
#     downstream that needs the UUID takes the last ARN segment, exactly as the
#     flow module does.
#   * `state` here is ACTIVE/ARCHIVED — the flow's lifecycle state, NOT its
#     publish status. Neither provider exposes Status (SAVED vs PUBLISHED), so
#     every flow created this way is published, and its content must therefore
#     pass Connect's flow validation at create time.

resource "awscc_connect_contact_flow" "console_owned" {
  for_each = local.flows_console_owned

  instance_arn = var.instance_arn
  name         = "${var.name_prefix}${each.key}"
  description  = try(each.value.description, null)
  type         = try(each.value.type, "CONTACT_FLOW")
  content      = jsonencode(local.rendered_flows[each.key].Content)
  state        = try(each.value.state, "ACTIVE")
  tags         = local.awscc_tags

  lifecycle {
    # Terraform provisions the flow, then stops owning its content. A designer's
    # console edit survives the next apply. Without this line, re-applying
    # silently reverts their work — which would make the demo lie.
    ignore_changes = [content]
  }
}

resource "awscc_connect_contact_flow" "managed" {
  for_each = local.flows_managed

  instance_arn = var.instance_arn
  name         = "${var.name_prefix}${each.key}"
  description  = try(each.value.description, null)
  type         = try(each.value.type, "CONTACT_FLOW")
  content      = jsonencode(local.rendered_flows[each.key].Content)
  state        = try(each.value.state, "ACTIVE")
  tags         = local.awscc_tags
}
