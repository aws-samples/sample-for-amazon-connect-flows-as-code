# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "instance_alias" {
  description = <<-EOT
    Alias for the Amazon Connect instance. Connect instance aliases are globally
    unique across ALL AWS accounts, so this must include something random. There
    is deliberately no default.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,60}[a-z0-9]$", var.instance_alias))
    error_message = "instance_alias must be 3-62 lowercase alphanumeric characters or hyphens, and may not start or end with a hyphen."
  }
}

variable "queue_names" {
  description = <<-EOT
    Queue names to create. These names are the contract between the two
    instances: the exporter encodes the NAME into each placeholder, and the
    consuming instance rebuilds the same placeholder key from its own resources.
    Both instances must therefore use the SAME names, which is why this defaults
    rather than being per-environment.
  EOT
  type        = list(string)
  default     = ["retail-support_en", "retail-priority_en"]

  validation {
    condition     = length(var.queue_names) >= 2
    error_message = "At least two queues are required: the demo re-points a flow from one to the other."
  }
}

variable "hours_of_operation_name" {
  description = "Name of the hours of operation. Queues require one, so this is not optional."
  type        = string
  default     = "retail-standard_hours"
}

variable "time_zone" {
  description = "IANA time zone for hours of operation and the data table."
  type        = string
  default     = "Europe/London"
}

variable "data_table_name" {
  description = "Name of the data table holding per-contact routing configuration."
  type        = string
  default     = "routing_config"
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
  default     = {}
}
