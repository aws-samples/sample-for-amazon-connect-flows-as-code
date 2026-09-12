# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Evaluation Form exporter for Amazon Connect."""

import logging
from exporters.base import BaseExporter

logger = logging.getLogger(__name__)


class EvaluationFormExporter(BaseExporter):
    """Exports Amazon Connect evaluation forms."""

    @property
    def resource_type(self):
        return "evaluation_form"

    @property
    def resource_type_plural(self):
        return "evaluation_forms"

    def _list_resources(self):
        results = []
        try:
            paginator = self._connect.get_paginator("list_evaluation_forms")
            for page in paginator.paginate(InstanceId=self._instance_id):
                for form in page.get("EvaluationFormSummaryList", []):
                    results.append({
                        "Id": form.get("EvaluationFormId"),
                        "Name": form.get("Title"),
                        "Arn": form.get("EvaluationFormArn"),
                    })
        except Exception as e:
            logger.warning("Failed to list evaluation forms: %s", e)
        logger.debug("Found %d evaluation forms", len(results))
        return results

    def _describe_resource(self, resource_id):
        resp = self._connect.describe_evaluation_form(InstanceId=self._instance_id, EvaluationFormId=resource_id)
        return resp.get("EvaluationForm", {})
