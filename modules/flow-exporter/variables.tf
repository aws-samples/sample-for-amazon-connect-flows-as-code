# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Connect Flow Export Module - Input Variables

variable "connect_instance_id" {
  description = "Amazon Connect instance ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.connect_instance_id))
    error_message = "The connect_instance_id must be a valid UUID format."
  }
}

variable "resource_types" {
  description = "List of resource types to export"
  type        = list(string)
  default = [
    "contact_flows",
    "contact_flow_modules",
    "views",
    "workspaces",
    "data_tables",
    "rules",
    "evaluation_forms"
  ]

  validation {
    condition = alltrue([
      for rt in var.resource_types : contains([
        "contact_flows", "contact_flow_modules", "views",
        "workspaces", "data_tables", "rules", "evaluation_forms"
      ], rt)
    ])
    error_message = "Invalid resource type. Supported: contact_flows, contact_flow_modules, views, workspaces, data_tables, rules, evaluation_forms."
  }
}

variable "s3_bucket_name" {
  description = "S3 bucket name for exports (created if not exists)"
  type        = string
  default     = null
}

variable "s3_key_prefix" {
  description = "Prefix for S3 object keys"
  type        = string
  default     = ""
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_reserved_concurrency" {
  description = "Lambda reserved concurrent executions"
  type        = number
  default     = null
}

variable "enable_cloudtrail_triggers" {
  description = "Enable CloudTrail event triggers for incremental export"
  type        = bool
  default     = true
}

variable "enable_scheduled_export" {
  description = "Enable scheduled export for rules"
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for rules export"
  type        = string
  default     = "rate(6 hours)"
}

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch log retention in days.

    Defaults to 365 to satisfy the one-year retention bar that security scanners
    apply (checkov CKV_AWS_338). The cost is immaterial here — the exporter logs
    a few kilobytes per invocation — and `terraform destroy` removes the log
    group entirely, so a reader who tears the sample down retains nothing.

    Lower it if you prefer; 30 is plenty for working through the walkthrough.
  EOT
  type        = number
  default     = 365
}

variable "export_all_versions" {
  description = "Export all versions of flow modules and views"
  type        = bool
  default     = false
}

variable "export_data_table_records" {
  description = "Export data table records (not just schema)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "additional_iam_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the Lambda execution role"
  type        = list(string)
  default     = []
}

variable "export_name_prefix" {
  description = "Only export flows/modules whose name starts with this prefix. Stripped from S3 key. Leave empty to export all."
  type        = string
  default     = ""
}

variable "boto3_version" {
  description = <<-EOT
    boto3 version bundled into the Lambda package. Must be >= 1.35.0 for the
    Amazon Connect data tables API. Pinned so the artifact is reproducible.
  EOT
  type        = string
  default     = "1.42.81"
}

variable "log_level" {
  description = "Log level for the exporter Lambda."
  type        = string
  default     = "INFO"
}

variable "permissions_boundary_name" {
  description = <<EOT
Name (not ARN) of an IAM permissions boundary policy to attach to the Lambda
execution role. Many organisations mandate a boundary on every role they
create. Leave empty to create the role without a boundary.
EOT
  type        = string
  default     = ""
}
