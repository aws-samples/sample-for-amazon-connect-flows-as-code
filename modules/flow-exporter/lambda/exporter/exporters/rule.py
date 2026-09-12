# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Contact Lens Rule exporter for Amazon Connect."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class RuleExporter(BaseExporter):
    """Exports Amazon Connect Contact Lens rules."""

    @property
    def resource_type(self):
        return "rule"

    @property
    def resource_type_plural(self):
        return "rules"

    def _list_resources(self):
        results = []
        try:
            paginator = self._connect.get_paginator("list_rules")
            for page in paginator.paginate(InstanceId=self._instance_id, PublishStatus="PUBLISHED"):
                for rule in page.get("RuleSummaryList", []):
                    results.append({"Id": rule.get("RuleId"), "Name": rule.get("Name"), "Arn": rule.get("RuleArn")})
        except Exception as e:
            logger.warning("Failed to list rules: %s", e)
        logger.debug("Found %d rules", len(results))
        return results

    def _describe_resource(self, resource_id):
        resp = self._connect.describe_rule(InstanceId=self._instance_id, RuleId=resource_id)
        return resp.get("Rule", {})
