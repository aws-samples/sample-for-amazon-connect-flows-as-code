# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Amazon Connect Flow Export Lambda Handler

Exports Amazon Connect resources to S3 with ARN/ID substitution
for cross-environment portability.

Supports three export modes:
- Full export: Export all resources of configured types
- Incremental export: Export single resource from CloudTrail event
"""

import json
import os
import logging

import boto3

from exporters import (
    ContactFlowExporter,
    ContactFlowModuleExporter,
    ViewExporter,
    WorkspaceExporter,
    DataTableExporter,
    RuleExporter,
    EvaluationFormExporter,
)
from transformers.reference_substitutor import ReferenceSubstitutor
from utils.content_parser import ContentParser
from utils.change_detector import ChangeDetector

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables
INSTANCE_ID = os.environ.get("CONNECT_INSTANCE_ID", "")
BUCKET = os.environ.get("S3_BUCKET", "")
PREFIX = os.environ.get("S3_KEY_PREFIX", "")
RESOURCE_TYPES = [t for t in os.environ.get("RESOURCE_TYPES", "").split(",") if t]
EXPORT_ALL_VERSIONS = os.environ.get("EXPORT_ALL_VERSIONS", "false") == "true"
EXPORT_DATA_TABLE_RECORDS = os.environ.get("EXPORT_DATA_TABLE_RECORDS", "true") != "false"
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
EXPORT_NAME_PREFIX = os.environ.get("EXPORT_NAME_PREFIX", "")

# Map CloudTrail event names to resource types
EVENT_TO_RESOURCE_TYPE = {
    "CreateContactFlow": "contact_flows",
    "UpdateContactFlowContent": "contact_flows",
    "UpdateContactFlowMetadata": "contact_flows",
    "CreateContactFlowModule": "contact_flow_modules",
    "UpdateContactFlowModuleContent": "contact_flow_modules",
    "UpdateContactFlowModuleMetadata": "contact_flow_modules",
    "CreateView": "views",
    "UpdateViewContent": "views",
    "UpdateViewMetadata": "views",
    "CreateEvaluationForm": "evaluation_forms",
    "UpdateEvaluationForm": "evaluation_forms",
}


def _get_export_type(event):
    """Determine export type from event."""
    if "export_type" in event:
        return event["export_type"]
    if event.get("source") == "aws.connect" and event.get("detail", {}).get("eventName"):
        return "incremental"
    if event.get("source") == "aws.events" or event.get("detail-type") == "Scheduled Event":
        return "scheduled"
    return "full"


def _extract_resource_id(event):
    """Extract resource ID from CloudTrail event."""
    detail = event.get("detail", {})
    for elements_key in ("responseElements", "requestParameters"):
        elements = detail.get(elements_key, {}) or {}
        for id_key in ("ContactFlowId", "ContactFlowModuleId", "ViewId", "EvaluationFormId"):
            if id_key in elements:
                return str(elements[id_key])
    return None


def _get_resource_type_from_event(event):
    """Get resource type from CloudTrail event."""
    event_name = event.get("detail", {}).get("eventName")
    return EVENT_TO_RESOURCE_TYPE.get(event_name) if event_name else None


def _build_exporter(resource_type, opts):
    """Build an exporter instance for the given resource type."""
    factories = {
        "contact_flows": lambda o: ContactFlowExporter(name_prefix=EXPORT_NAME_PREFIX, **o),
        "contact_flow_modules": lambda o: ContactFlowModuleExporter(
            export_all_versions=EXPORT_ALL_VERSIONS, name_prefix=EXPORT_NAME_PREFIX, **o
        ),
        "views": lambda o: ViewExporter(export_all_versions=EXPORT_ALL_VERSIONS, name_prefix=EXPORT_NAME_PREFIX, **o),
        "workspaces": lambda o: WorkspaceExporter(**o),
        "data_tables": lambda o: DataTableExporter(export_records=EXPORT_DATA_TABLE_RECORDS, **o),
        "rules": lambda o: RuleExporter(**o),
        "evaluation_forms": lambda o: EvaluationFormExporter(**o),
    }
    factory = factories.get(resource_type)
    if not factory:
        logger.warning("Unknown resource type: %s", resource_type)
        return None
    return factory(opts)


def handler(event, context):
    """Main Lambda handler."""
    logger.info("Export Lambda invoked, requestId=%s", context.aws_request_id)
    logger.debug("Event: %s", json.dumps(event, default=str))

    if not INSTANCE_ID:
        raise ValueError("CONNECT_INSTANCE_ID environment variable is required")
    if not BUCKET:
        raise ValueError("S3_BUCKET environment variable is required")

    connect_client = boto3.client("connect")
    s3_client = boto3.client("s3")

    reference_substitutor = ReferenceSubstitutor(connect_client, INSTANCE_ID, name_prefix=EXPORT_NAME_PREFIX)
    content_parser = ContentParser()
    change_detector = ChangeDetector(s3_client, BUCKET, PREFIX)

    exporter_opts = {
        "connect_client": connect_client,
        "s3_client": s3_client,
        "instance_id": INSTANCE_ID,
        "bucket": BUCKET,
        "prefix": PREFIX,
        "reference_substitutor": reference_substitutor,
        "content_parser": content_parser,
        "change_detector": change_detector,
    }

    export_type = _get_export_type(event)
    results = []

    if export_type == "full":
        types = event.get("resource_types") or RESOURCE_TYPES
        for rt in types:
            exporter = _build_exporter(rt, exporter_opts)
            if exporter:
                results.extend(exporter.export_all())

    elif export_type == "incremental":
        resource_type = _get_resource_type_from_event(event)
        resource_id = _extract_resource_id(event)
        if not resource_type or not resource_id:
            logger.error("Could not extract resource type or ID from event")
            results.append({
                "resourceType": "unknown",
                "resourceName": "unknown",
                "resourceId": "unknown",
                "status": "failed",
                "errorMessage": "Could not extract resource type or ID from CloudTrail event",
                "changed": False,
            })
        else:
            exporter = _build_exporter(resource_type, exporter_opts)
            if exporter:
                results.append(exporter.export_single(resource_id))

    elif export_type == "scheduled":
        exporter = RuleExporter(**exporter_opts)
        results.extend(exporter.export_all())

    # Build response
    exported = [r["resourceName"] for r in results if r.get("status") == "exported"]
    skipped = [r["resourceName"] for r in results if r.get("status") == "skipped"]
    failed = [
        {"name": r["resourceName"], "error": r.get("errorMessage", "Unknown error")}
        for r in results
        if r.get("status") == "failed"
    ]

    response = {
        "status": "partial_failure" if failed else "success",
        "exported": exported,
        "skipped": skipped,
        "failed": failed,
        "summary": {
            "total": len(results),
            "exported": len(exported),
            "skipped": len(skipped),
            "failed": len(failed),
        },
    }

    logger.info("Export completed: %s", json.dumps(response["summary"]))
    return response
