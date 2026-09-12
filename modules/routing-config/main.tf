# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Data table records: the environment-specific values flows read at contact time.
# =============================================================================
#
# This is the "dynamic reference" half of the pattern. Rather than embedding a
# queue ID or a flow ID in the flow JSON — where it would have to be rewritten
# on every promotion — Terraform writes those IDs into a data table row, and the
# flow looks them up per contact:
#
#     Set working queue -> Set dynamically -> $.DataTables.RoutingLookup.QueueId
#
# The row therefore holds THIS instance's IDs, and the flow JSON stays portable.
# It is the AWS Prescriptive Guidance recommendation to "save environment
# specific ARN references ... as resources are provisioned", made concrete.
#
# Applied AFTER flow-deployer, because a row carries the fallback flow's ID.
# There is no dependency cycle: the flow does not reference the row at plan time.

locals {
  # Flatten { record_key => { column => value } } into one entry per cell, so
  # each record can be built from a list of attribute_id/value pairs.
  cells = {
    for rk, columns in var.records : rk => [
      for col, val in columns : {
        attribute_id    = var.data_table_attribute_ids[col]
        attribute_value = tostring(val)
      }
      # The primary key column is supplied separately as primary_values.
      if col != var.primary_column
    ]
  }
}

resource "awscc_connect_data_table_record" "this" {
  for_each = var.records

  instance_arn   = var.instance_arn
  data_table_arn = var.data_table_arn

  data_table_record = {
    primary_values = [{
      attribute_id    = var.data_table_attribute_ids[var.primary_column]
      attribute_value = tostring(each.value[var.primary_column])
    }]

    values = local.cells[each.key]
  }
}
