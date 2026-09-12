# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "instance_id" {
  description = "Amazon Connect instance ID."
  value       = aws_connect_instance.this.id
}

output "instance_arn" {
  description = "Amazon Connect instance ARN."
  value       = aws_connect_instance.this.arn
}

output "instance_alias" {
  description = "Amazon Connect instance alias, echoed back for convenience in the walkthrough."
  value       = aws_connect_instance.this.instance_alias
}

# The registry in flow-deployer is keyed on resource NAME, so every output below
# is a map keyed by name rather than by Terraform resource key.

output "queue_ids" {
  description = "Queue name -> queue ID. Flow blocks reference queues by ID, not ARN."
  value       = { for name, q in aws_connect_queue.this : name => q.queue_id }
}

output "queue_arns" {
  description = "Queue name -> queue ARN."
  value       = { for name, q in aws_connect_queue.this : name => q.arn }
}

output "hours_of_operation_id" {
  description = "Hours of operation ID."
  value       = aws_connect_hours_of_operation.this.hours_of_operation_id
}

output "hours_of_operation_name" {
  description = "Hours of operation name, used to build its placeholder key."
  value       = aws_connect_hours_of_operation.this.name
}

output "data_table_name" {
  description = "Data table name. The exporter encodes this into $${data_table_<b64>}."
  value       = awscc_connect_data_table.this.name
}

output "data_table_id" {
  description = <<-EOT
    Data table ID. A flow's Data table block stores the table by ID, so this is
    what the $${data_table_<b64>} placeholder resolves to.

    Derived from the ARN rather than read from `id`: awscc sets `id` to the Cloud
    Control primary identifier, which for this resource is a composite
    ("instance_arn|arn"), not the bare table UUID a flow needs.
  EOT
  value       = regex("[^/]+$", awscc_connect_data_table.this.arn)
}

output "data_table_arn" {
  description = "Data table ARN, needed to attach attributes and records."
  value       = awscc_connect_data_table.this.arn
}

output "data_table_attribute_ids" {
  description = <<-EOT
    Column name -> attribute ID. Records address cells by attribute ID rather
    than by column name, so modules/routing-config needs this map.
  EOT
  value       = { for name, a in awscc_connect_data_table_attribute.this : name => a.attribute_id }
}
