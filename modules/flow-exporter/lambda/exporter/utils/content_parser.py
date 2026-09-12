# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Content parser utility for Amazon Connect resource exports.

Parses stringified JSON Content fields into proper JSON objects and
formats JSON with consistent formatting for git-friendly output.
"""

import json
import logging

logger = logging.getLogger(__name__)

CONTENT_FIELD_RESOURCE_TYPES = {"contact_flow", "contact_flow_module", "view"}


def _sort_keys(obj):
    """Recursively sort dictionary keys for deterministic output."""
    if isinstance(obj, dict):
        return {k: _sort_keys(v) for k, v in sorted(obj.items())}
    if isinstance(obj, list):
        return [_sort_keys(item) for item in obj]
    return obj


class ContentParser:
    """Parse and format Amazon Connect resource content."""

    def parse(self, resource, resource_type):
        """Parse Content field if present and stringified."""
        if not isinstance(resource, dict):
            return resource
        if resource_type not in CONTENT_FIELD_RESOURCE_TYPES:
            return resource
        if "Content" not in resource:
            return resource

        content = resource["Content"]
        if content is None or isinstance(content, dict):
            return resource
        if not isinstance(content, str) or not content.strip():
            return resource

        try:
            parsed = json.loads(content)
            return {**resource, "Content": parsed}
        except (json.JSONDecodeError, TypeError):
            logger.warning("Failed to parse Content field as JSON for resource type '%s'", resource_type)
            return resource

    def format_json(self, data):
        """Format data as JSON with 2-space indent and sorted keys."""
        sorted_data = _sort_keys(data)
        return json.dumps(sorted_data, indent=2, ensure_ascii=False)
