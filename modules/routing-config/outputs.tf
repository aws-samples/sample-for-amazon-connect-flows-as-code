# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "record_ids" {
  description = "Record key -> data table record ID."
  value       = { for k, r in awscc_connect_data_table_record.this : k => r.record_id }
}
