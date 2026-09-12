# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Contact Flow Module exporter for Amazon Connect."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class ContactFlowModuleExporter(BaseExporter):
    """Exports Amazon Connect flow modules as portable templates."""

    def __init__(self, export_all_versions=False, **kwargs):
        super().__init__(**kwargs)
        self._export_all_versions = export_all_versions

    @property
    def resource_type(self):
        return "contact_flow_module"

    @property
    def resource_type_plural(self):
        return "contact_flow_modules"

    def _list_resources(self):
        results = []
        paginator = self._connect.get_paginator("list_contact_flow_modules")
        for page in paginator.paginate(InstanceId=self._instance_id):
            for mod in page.get("ContactFlowModulesSummaryList", []):
                results.append({"Id": mod.get("Id"), "Name": mod.get("Name"), "Arn": mod.get("Arn")})
        logger.debug("Found %d contact flow modules", len(results))
        return results

    def _describe_resource(self, resource_id):
        resp = self._connect.describe_contact_flow_module(InstanceId=self._instance_id, ContactFlowModuleId=resource_id)
        return resp.get("ContactFlowModule", {})
