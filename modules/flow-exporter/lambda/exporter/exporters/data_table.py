# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Data Table exporter for Amazon Connect (placeholder)."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class DataTableExporter(BaseExporter):
    """Exports Amazon Connect data tables. Not implemented: listing and describe are
    not implemented, so this exporter is excluded from the demo's resource_types."""

    def __init__(self, export_records=True, **kwargs):
        super().__init__(**kwargs)
        self._export_records = export_records

    @property
    def resource_type(self):
        return "data_table"

    @property
    def resource_type_plural(self):
        return "data_tables"

    def _list_resources(self):
        logger.warning("Data table listing not yet fully implemented")
        return []

    def _describe_resource(self, resource_id):
        logger.warning("Data table describe not yet fully implemented")
        return {"Id": resource_id}

    def export_single(self, resource_id):
        """Export a data table with schema and optionally records."""
        logger.info("Exporting data table '%s' (records: %s)", resource_id, self._export_records)
        try:
            resource = self._describe_resource(resource_id)
            name = resource.get("Name", "unnamed")
            arn = resource.get("Arn", "")

            transformed = self._transform_resource(resource)
            with_meta = self._add_export_metadata(transformed, arn)
            with_meta["_export_metadata"]["records_exported"] = self._export_records

            content = self._parser.format_json(with_meta)
            s3_key = self._s3_key(name, "schema")
            changed = self._change_detector.has_changed(s3_key, content)

            if changed:
                self._write_to_s3(s3_key, content)
                logger.info("Exported data table schema '%s'", name)

            return {"resourceType": self.resource_type, "resourceName": name,
                    "resourceId": resource_id, "status": "exported" if changed else "skipped",
                    "s3Key": s3_key, "changed": changed}
        except Exception as e:
            logger.error("Failed to export data table '%s': %s", resource_id, e)
            return {"resourceType": self.resource_type, "resourceName": "unknown",
                    "resourceId": resource_id, "status": "failed", "errorMessage": str(e), "changed": False}
