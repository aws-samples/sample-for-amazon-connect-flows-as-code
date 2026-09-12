# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Workspace exporter for Amazon Connect (placeholder)."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class WorkspaceExporter(BaseExporter):
    """Exports Amazon Connect agent workspaces. Not implemented."""

    @property
    def resource_type(self):
        return "workspace"

    @property
    def resource_type_plural(self):
        return "workspaces"

    def _list_resources(self):
        logger.warning("Workspace listing not yet implemented - Connect API may not support this")
        return []

    def _describe_resource(self, resource_id):
        logger.warning("Workspace describe not yet implemented")
        return {"Id": resource_id}
