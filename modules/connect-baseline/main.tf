# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Baseline Amazon Connect resources, identical in both instances.
# =============================================================================
#
# This module is called ONCE PER ROOT MODULE, so applying both root modules
# produces two Connect instances whose resources share NAMES but not ARNs. That
# is the whole premise of the demo: the exporter encodes the resource *name*
# into each placeholder, and the consuming instance rebuilds the same
# placeholder key from its own state.
#
# It creates the resources a flow needs to reference, and nothing else:
#
#   instance -> hours of operation -> queues        (queues require HoO)
#            -> data table -> attributes           (columns, no rows yet)
#
# Data table RECORDS are deliberately NOT created here. A record has to carry
# the fallback flow's ID, and flows are created later by flow-deployer. Records
# therefore live in modules/routing-config, applied after both.

locals {
  # Queue index by name, so callers can look up "retail-support_en" without
  # caring about ordering.
  queue_map = { for name in var.queue_names : name => name }

  # Data table columns. `primary` marks the lookup key; the rest are the values
  # a flow reads at contact time.
  #
  # QueueId and FallbackFlowId hold environment-specific identifiers written by
  # Terraform. GreetingText is plain copy, and lives here so that changing what
  # the caller hears is a data edit rather than a flow deployment.
  data_table_attributes = {
    ConfigKey      = { value_type = "TEXT", primary = true }
    QueueId        = { value_type = "TEXT", primary = false }
    FallbackFlowId = { value_type = "TEXT", primary = false }
    GreetingText   = { value_type = "TEXT", primary = false }
  }
}

resource "aws_connect_instance" "this" {
  instance_alias           = var.instance_alias
  identity_management_type = "CONNECT_MANAGED"

  inbound_calls_enabled  = true
  outbound_calls_enabled = true

  # Flow logs make the walkthrough debuggable: if a dynamic reference fails to
  # resolve at contact time, the error shows up in CloudWatch.
  contact_flow_logs_enabled = true
}

resource "aws_connect_hours_of_operation" "this" {
  instance_id = aws_connect_instance.this.id
  name        = var.hours_of_operation_name
  description = "Standard hours. Required by every queue."
  time_zone   = var.time_zone

  dynamic "config" {
    for_each = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY"]

    content {
      day = config.value

      start_time {
        hours   = 8
        minutes = 0
      }

      end_time {
        hours   = 18
        minutes = 0
      }
    }
  }

  tags = var.tags
}

resource "aws_connect_queue" "this" {
  for_each = local.queue_map

  instance_id           = aws_connect_instance.this.id
  name                  = each.value
  description           = "Demo queue ${each.value}"
  hours_of_operation_id = aws_connect_hours_of_operation.this.hours_of_operation_id

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Data table: the store the flows read at contact time
# -----------------------------------------------------------------------------

resource "awscc_connect_data_table" "this" {
  instance_arn = aws_connect_instance.this.arn
  name         = var.data_table_name
  description  = "Per-contact routing configuration read by flows at runtime."

  # PUBLISHED is required for a flow to read the table. SAVED leaves it a draft.
  status = "PUBLISHED"

  time_zone = var.time_zone

  # Optimistic-concurrency locking, and it has to be NONE for a table whose rows
  # Terraform owns.
  #
  # Any other level (DATA_TABLE, PRIMARY_VALUE, ATTRIBUTE, VALUE) makes a write
  # supply the current lock token for the scope it names. AWS::Connect::
  # DataTableRecord has no field to carry one, so Cloud Control writes without it
  # and the service rejects the row:
  #
  #   Failed to create DataTableRecord for AttributeName(s): GreetingText with
  #   Exception: Provided lock does not match expected lock <uuid>
  #
  # Locking exists to stop two console editors clobbering each other. When
  # Terraform is the only writer, state serialises the writes instead and the
  # lock has nothing left to protect. A table that humans edit in the console
  # should keep a lock level — and then its rows should not be Terraform-managed.
  value_lock_level = "NONE"

  tags = [for k, v in var.tags : { key = k, value = v }]
}

resource "awscc_connect_data_table_attribute" "this" {
  for_each = local.data_table_attributes

  instance_arn   = aws_connect_instance.this.arn
  data_table_arn = awscc_connect_data_table.this.arn
  name           = each.key
  value_type     = each.value.value_type
  primary        = each.value.primary
}
