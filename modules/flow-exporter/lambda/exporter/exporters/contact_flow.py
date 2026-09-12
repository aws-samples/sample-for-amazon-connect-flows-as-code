# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Contact Flow exporter for Amazon Connect."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class ContactFlowExporter(BaseExporter):
    """Exports Amazon Connect contact flows as portable templates."""

    @property
    def resource_type(self):
        return "contact_flow"

    @property
    def resource_type_plural(self):
        return "contact_flows"

    def _list_resources(self):
        results = []
        paginator = self._connect.get_paginator("list_contact_flows")
        for page in paginator.paginate(InstanceId=self._instance_id):
            for flow in page.get("ContactFlowSummaryList", []):
                results.append({"Id": flow.get("Id"), "Name": flow.get("Name"), "Arn": flow.get("Arn")})
        logger.debug("Found %d contact flows", len(results))
        return results

    def _describe_resource(self, resource_id):
        resp = self._connect.describe_contact_flow(InstanceId=self._instance_id, ContactFlowId=resource_id)
        return resp.get("ContactFlow", {})
