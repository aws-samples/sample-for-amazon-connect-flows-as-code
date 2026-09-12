# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Connect Flow Export Module - Main Orchestration
# ===============================================
# Exports Amazon Connect resources from a development environment,
# transforms them for cross-environment portability through ARN/ID substitution,
# and stores them in S3 in a git-friendly format.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id           = data.aws_caller_identity.current.account_id
  region               = data.aws_region.current.region
  connect_instance_arn = "arn:aws:connect:${local.region}:${local.account_id}:instance/${var.connect_instance_id}"
  name_prefix          = "connect-flow-export"
  environment          = var.s3_key_prefix != "" ? var.s3_key_prefix : "dev"

  supported_resource_types = [
    "contact_flows",
    "contact_flow_modules",
    "views",
    "workspaces",
    "data_tables",
    "rules",
    "evaluation_forms"
  ]

  exporter_log_group_name = "/aws/lambda/${local.name_prefix}-exporter"
}
