# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Base exporter class for Amazon Connect resource exports.

Provides common interface and shared functionality for exporting
resources to S3 with change detection and ARN substitution.
"""

import re
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


class BaseExporter:
    """Base class for all resource-specific exporters."""

    def __init__(self, connect_client, s3_client, instance_id, bucket,
                 prefix="", reference_substitutor=None, content_parser=None,
                 change_detector=None, name_prefix=""):
        self._connect = connect_client
        self._s3 = s3_client
        self._instance_id = instance_id
        self._bucket = bucket
        self._prefix = prefix
        self._name_prefix = name_prefix
        self._substitutor = reference_substitutor
        self._parser = content_parser
        self._change_detector = change_detector

    @property
    def resource_type(self):
        """Return the singular resource type name, e.g. 'contact_flow'."""
        raise NotImplementedError

    @property
    def resource_type_plural(self):
        """Return the plural resource type name, used in S3 key prefixes."""
        raise NotImplementedError

    def _list_resources(self):
        """Return list of dicts with Id, Name, Arn keys."""
        raise NotImplementedError

    def _describe_resource(self, resource_id):
        """Return dict of resource details."""
        raise NotImplementedError

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _sanitize_name(name):
        s = name.lower().replace(" ", "-")
        s = re.sub(r"[^a-z0-9\-_]", "", s)
        s = re.sub(r"-+", "-", s).strip("-")
        return s or "unnamed"

    def _s3_key(self, resource_name, suffix=None):
        sanitized = self._sanitize_name(resource_name)
        filename = f"{sanitized}-{suffix}.json.tpl" if suffix else f"{sanitized}.json.tpl"
        if self._prefix:
            return f"{self._prefix.rstrip('/')}/{self.resource_type_plural}/{filename}"
        return f"{self.resource_type_plural}/{filename}"

    def _add_export_metadata(self, resource, resource_arn):
        return {
            **resource,
            "_export_metadata": {
                "exported_at": datetime.now(timezone.utc).isoformat(),
                "source_instance_id": self._instance_id,
                "resource_arn": resource_arn,
            },
        }

    def _transform_resource(self, resource):
        parsed = self._parser.parse(resource, self.resource_type)
        if self._substitutor:
            return self._substitutor.transform(parsed, self.resource_type)
        return parsed

    def _write_to_s3(self, key, content):
        filename = key.rsplit("/", 1)[-1]
        self._s3.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=content.encode("utf-8"),
            ContentType="application/octet-stream",
            ContentDisposition=f'attachment; filename="{filename}"',
        )
        logger.debug("Wrote to s3://%s/%s", self._bucket, key)

    @staticmethod
    def _strip_non_deployable(resource):
        """Keep only Content, Description, Type for deployment."""
        return {k: v for k, v in resource.items() if k in ("Content", "Description", "Type")}

    # ------------------------------------------------------------------
    # Export methods
    # ------------------------------------------------------------------

    def export_single(self, resource_id):
        """Export a single resource by ID."""
        logger.info("Exporting single %s with ID '%s'", self.resource_type, resource_id)
        try:
            resource = self._describe_resource(resource_id)
            name = resource.get("Name", "unnamed")

            if self._name_prefix and not name.startswith(self._name_prefix):
                logger.info("Skipped %s '%s' - does not start with '%s'", self.resource_type, name, self._name_prefix)
                return {"resourceType": self.resource_type, "resourceName": name,
                        "resourceId": resource_id, "status": "skipped", "changed": False}

            export_name = name[len(self._name_prefix):] if self._name_prefix else name
            transformed = self._transform_resource(resource)
            deployable = self._strip_non_deployable(transformed)
            content = self._parser.format_json(deployable)
            s3_key = self._s3_key(export_name)

            changed = self._change_detector.has_changed(s3_key, content)
            if changed:
                self._write_to_s3(s3_key, content)
                logger.info("Exported %s '%s' to s3://%s/%s", self.resource_type, name, self._bucket, s3_key)
                return {"resourceType": self.resource_type, "resourceName": name,
                        "resourceId": resource_id, "status": "exported", "s3Key": s3_key, "changed": True}

            logger.info("Skipped %s '%s' - no changes", self.resource_type, name)
            return {"resourceType": self.resource_type, "resourceName": name,
                    "resourceId": resource_id, "status": "skipped", "s3Key": s3_key, "changed": False}
        except Exception as e:
            logger.error("Failed to export %s '%s': %s", self.resource_type, resource_id, e)
            return {"resourceType": self.resource_type, "resourceName": "unknown",
                    "resourceId": resource_id, "status": "failed", "errorMessage": str(e), "changed": False}

    def export_all(self):
        """Export all resources of this type."""
        logger.info("Starting full export of %s resources", self.resource_type)
        results = []
        try:
            resources = self._list_resources()
            if self._name_prefix:
                before = len(resources)
                resources = [r for r in resources if r.get("Name", "").startswith(self._name_prefix)]
                logger.info("Filtered %s by prefix '%s': %d -> %d",
                            self.resource_type, self._name_prefix, before, len(resources))
            logger.info("Found %d %s resources to export", len(resources), self.resource_type)
            for r in resources:
                if not r.get("Id"):
                    continue
                results.append(self.export_single(r["Id"]))
        except Exception as e:
            logger.error("Failed to list %s resources: %s", self.resource_type, e)
            results.append({"resourceType": self.resource_type, "resourceName": "list_operation",
                            "resourceId": "", "status": "failed",
                            "errorMessage": f"Failed to list resources: {e}", "changed": False})

        exported = sum(1 for r in results if r.get("status") == "exported")
        skipped = sum(1 for r in results if r.get("status") == "skipped")
        failed = sum(1 for r in results if r.get("status") == "failed")
        logger.info("Completed %s export: %d exported, %d skipped, %d failed",
                    self.resource_type, exported, skipped, failed)
        return results
