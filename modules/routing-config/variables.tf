# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "instance_arn" {
  description = "Amazon Connect instance ARN."
  type        = string
}

variable "data_table_arn" {
  description = "ARN of the data table the records belong to."
  type        = string
}

variable "data_table_attribute_ids" {
  description = <<-EOT
    Column name -> attribute ID, from connect-baseline. Records address cells by
    attribute ID rather than by column name, so this mapping is required.
  EOT
  type        = map(string)
}

variable "primary_column" {
  description = "Name of the primary-key column. Its value is passed as primary_values."
  type        = string
  default     = "ConfigKey"
}

variable "records" {
  description = <<-EOT
    Records to write, as { record_key => { column_name => value } }. Every
    record must include the primary column. Values are coerced to strings
    because a data table cell is text.

    Example:
      {
        retail = {
          ConfigKey      = "retail"
          QueueId        = "<this instance's queue id>"
          FallbackFlowId = "<this instance's flow id>"
          GreetingText   = "Thanks for calling."
        }
      }
  EOT
  type        = map(map(string))

  validation {
    condition     = alltrue([for k, v in var.records : contains(keys(v), var.primary_column)])
    error_message = "Every record must include the primary column."
  }
}
