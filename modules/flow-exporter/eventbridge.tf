# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Connect Flow Export Module - EventBridge Rules

locals {
  cloudtrail_event_patterns = {
    contact_flows = {
      event_names = [
        "CreateContactFlow", "UpdateContactFlowContent",
        "UpdateContactFlowMetadata", "UpdateContactFlowName",
      ]
      enabled = contains(var.resource_types, "contact_flows") && var.enable_cloudtrail_triggers
    }
    contact_flow_modules = {
      event_names = [
        "CreateContactFlowModule", "UpdateContactFlowModuleContent",
        "UpdateContactFlowModuleMetadata",
      ]
      enabled = contains(var.resource_types, "contact_flow_modules") && var.enable_cloudtrail_triggers
    }
    views = {
      event_names = ["CreateView", "UpdateViewContent", "UpdateViewMetadata"]
      enabled     = contains(var.resource_types, "views") && var.enable_cloudtrail_triggers
    }
    evaluation_forms = {
      event_names = ["CreateEvaluationForm", "UpdateEvaluationForm", "ActivateEvaluationForm"]
      enabled     = contains(var.resource_types, "evaluation_forms") && var.enable_cloudtrail_triggers
    }
  }

  enabled_cloudtrail_rules = {
    for k, v in local.cloudtrail_event_patterns : k => v if v.enabled
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name = "${local.name_prefix}-dlq"

  # SQS-managed server-side encryption. Chosen over a customer-managed KMS key
  # deliberately: a CMK carries a monthly charge, and the only thing this queue
  # ever holds is a failed EventBridge event naming a Connect resource — no
  # contact data and no credentials.
  sqs_managed_sse_enabled = true

  message_retention_seconds = 1209600
  tags                      = merge(var.tags, { Name = "${local.name_prefix}-dlq" })
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeSendMessage"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:events:${local.region}:${local.account_id}:rule/${local.name_prefix}-*"
        }
      }
    }]
  })
}

# CloudTrail Event Rules
resource "aws_cloudwatch_event_rule" "cloudtrail" {
  for_each    = local.enabled_cloudtrail_rules
  name        = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  description = "Triggers export Lambda when ${each.key} are created or updated"

  event_pattern = jsonencode({
    source      = ["aws.connect"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["connect.amazonaws.com"]
      eventName   = each.value.event_names
    }
  })

  tags = merge(var.tags, {
    Name         = "${local.name_prefix}-${replace(each.key, "_", "-")}"
    ResourceType = each.key
  })
}

resource "aws_cloudwatch_event_target" "cloudtrail" {
  for_each  = local.enabled_cloudtrail_rules
  rule      = aws_cloudwatch_event_rule.cloudtrail[each.key].name
  target_id = "export-lambda"
  arn       = aws_lambda_function.exporter.arn

  dead_letter_config { arn = aws_sqs_queue.dlq.arn }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

# Scheduled Rule for Rules Export
resource "aws_cloudwatch_event_rule" "scheduled_rules" {
  count               = contains(var.resource_types, "rules") && var.enable_scheduled_export ? 1 : 0
  name                = "${local.name_prefix}-scheduled-rules"
  description         = "Scheduled export of Contact Lens Rules"
  schedule_expression = var.schedule_expression
  tags                = merge(var.tags, { Name = "${local.name_prefix}-scheduled-rules", ResourceType = "rules" })
}

resource "aws_cloudwatch_event_target" "scheduled_rules" {
  count     = contains(var.resource_types, "rules") && var.enable_scheduled_export ? 1 : 0
  rule      = aws_cloudwatch_event_rule.scheduled_rules[0].name
  target_id = "export-lambda"
  arn       = aws_lambda_function.exporter.arn

  input = jsonencode({ export_type = "scheduled", resource_types = ["rules"] })
  dead_letter_config { arn = aws_sqs_queue.dlq.arn }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}
