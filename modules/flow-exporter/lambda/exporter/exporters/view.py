# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""View exporter for Amazon Connect."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class ViewExporter(BaseExporter):
    """Exports Amazon Connect agent workspace views."""

    def __init__(self, export_all_versions=False, **kwargs):
        super().__init__(**kwargs)
        self._export_all_versions = export_all_versions

    @property
    def resource_type(self):
        return "view"

    @property
    def resource_type_plural(self):
        return "views"

    def _list_resources(self):
        results = []
        paginator = self._connect.get_paginator("list_views")
        for page in paginator.paginate(InstanceId=self._instance_id):
            for view in page.get("ViewsSummaryList", []):
                results.append({"Id": view.get("Id"), "Name": view.get("Name"), "Arn": view.get("Arn")})
        logger.debug("Found %d views", len(results))
        return results

    def _describe_resource(self, resource_id):
        resp = self._connect.describe_view(InstanceId=self._instance_id, ViewId=resource_id)
        return resp.get("View", {})
