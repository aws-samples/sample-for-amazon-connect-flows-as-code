# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Connect Flow Export Module - IAM Roles and Policies

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution-role"
  # Optional: attach an organisation-mandated permissions boundary.
  # Leave var.permissions_boundary_name empty to skip it.
  permissions_boundary = var.permissions_boundary_name != "" ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary_name}" : null
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-lambda-execution-role" })
}

# Connect Read Access
data "aws_iam_policy_document" "connect_read_access" {
  statement {
    sid    = "ConnectInstanceScopedReadAccess"
    effect = "Allow"
    actions = [
      "connect:DescribeContactFlow", "connect:DescribeContactFlowModule",
      "connect:DescribeView", "connect:DescribeInstance",
      "connect:ListContactFlows", "connect:ListContactFlowModules",
      "connect:ListContactFlowVersions", "connect:ListContactFlowModuleVersions",
      "connect:ListViews", "connect:ListViewVersions",
      "connect:ListEvaluationForms", "connect:ListRules",
      "connect:DescribeEvaluationForm", "connect:DescribeRule",
      "connect:ListTagsForResource",
      "connect:ListQueues", "connect:DescribeQueue",
      "connect:ListHoursOfOperations", "connect:DescribeHoursOfOperation",
      "connect:ListRoutingProfiles", "connect:DescribeRoutingProfile",
      "connect:ListPrompts", "connect:DescribePrompt",
      "connect:ListDataTables", "connect:DescribeDataTable", "connect:ListDataTableAttributes", "connect:DescribeDataTableAttribute",
      "connect:ListLambdaFunctions", "connect:DescribeLambdaFunction",
      "connect:ListBots", "connect:DescribeBot", "connect:ListQuickConnects", "connect:DescribeQuickConnect", "connect:ListIntegrationAssociations", "connect:DescribeIntegrationAssociation",
    ]
    resources = [local.connect_instance_arn, "${local.connect_instance_arn}/*"]
  }

  # There is deliberately no account-level statement here. An earlier version
  # granted connect:ListInstances, SearchContactFlows and SearchContactFlowModules
  # on resources = ["*"], because those three APIs are not instance-scopable. The
  # exporter calls none of them: every Connect API it uses is in the statement
  # above and is scoped to this instance's ARN. Removing the statement resolved
  # checkov CKV_AWS_356 by deletion rather than by suppression, which is the
  # better outcome.
}

resource "aws_iam_policy" "connect_read_access" {
  name   = "${local.name_prefix}-connect-read-access"
  policy = data.aws_iam_policy_document.connect_read_access.json
  tags   = merge(var.tags, { Name = "${local.name_prefix}-connect-read-access" })
}

# Chime SDK Voice Read Access
# Needed so the exporter can resolve Chime Voice Connector ARNs
# referenced in contact flows (e.g. TransferParticipantToThirdParty
# actions) to portable ${voice_connector_<name>} placeholders.

data "aws_iam_policy_document" "chime_read_access" {
  statement {
    sid    = "ChimeSDKVoiceListAccess"
    effect = "Allow"
    actions = [
      "chime:ListVoiceConnectors",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "chime_read_access" {
  name   = "${local.name_prefix}-chime-read-access"
  policy = data.aws_iam_policy_document.chime_read_access.json
  tags   = merge(var.tags, { Name = "${local.name_prefix}-chime-read-access" })
}

# S3 Write Access
locals {
  s3_iam_object_prefix   = var.s3_key_prefix != "" ? "${var.s3_key_prefix}/*" : "*"
  exporter_log_group_arn = "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.exporter_log_group_name}:*"
}

data "aws_iam_policy_document" "s3_write_access" {
  statement {
    sid       = "S3ObjectAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.export.arn}/${local.s3_iam_object_prefix}"]
  }
  statement {
    sid       = "S3ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.export.arn]

    dynamic "condition" {
      for_each = var.s3_key_prefix != "" ? [1] : []
      content {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["${var.s3_key_prefix}/*"]
      }
    }
  }
}

resource "aws_iam_policy" "s3_write_access" {
  name   = "${local.name_prefix}-s3-write-access"
  policy = data.aws_iam_policy_document.s3_write_access.json
  tags   = merge(var.tags, { Name = "${local.name_prefix}-s3-write-access" })
}

# CloudWatch Logs
data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid       = "CreateLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.exporter_log_group_name}"]
  }
  statement {
    sid       = "WriteLogEvents"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.exporter_log_group_arn]
  }
}

resource "aws_iam_policy" "cloudwatch_logs" {
  name   = "${local.name_prefix}-cloudwatch-logs"
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
  tags   = merge(var.tags, { Name = "${local.name_prefix}-cloudwatch-logs" })
}

# Policy Attachments
# Lets the function write failed asynchronous invocations to its DLQ. Without
# this the dead_letter_config on the function fails silently, which is worse
# than not having it.
data "aws_iam_policy_document" "dlq_send" {
  statement {
    sid    = "SendFailedInvocationsToDlq"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [aws_sqs_queue.dlq.arn]
  }

  # X-Ray permissions are NOT defined here. Its write APIs take no resource
  # qualifier — trace segments are not addressable resources — so any inline
  # policy for them must use "*", which is a finding no reviewer should have to
  # waive. AWS publishes a managed policy for exactly this, so the wildcard lives
  # in a policy AWS has already reviewed rather than in this sample. See the
  # attachment below, and the code guidelines: "Use AWS Managed policies whenever
  # possible."
}

resource "aws_iam_policy" "dlq_send" {
  name   = "${local.name_prefix}-dlq-send"
  policy = data.aws_iam_policy_document.dlq_send.json
  tags   = merge(var.tags, { Name = "${local.name_prefix}-dlq-send" })
}

# The AWS managed policy for X-Ray writes. Pre-reviewed by AWS, so this sample
# contains no wildcard IAM resource of its own.
resource "aws_iam_role_policy_attachment" "xray_write" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "connect_read_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.connect_read_access.arn
}

resource "aws_iam_role_policy_attachment" "chime_read_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.chime_read_access.arn
}

resource "aws_iam_role_policy_attachment" "s3_write_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.s3_write_access.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

resource "aws_iam_role_policy_attachment" "dlq_send" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.dlq_send.arn
}

resource "aws_iam_role_policy_attachment" "additional_policies" {
  for_each   = toset(var.additional_iam_policy_arns)
  role       = aws_iam_role.lambda_execution.name
  policy_arn = each.value
}

