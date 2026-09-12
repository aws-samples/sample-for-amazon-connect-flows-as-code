# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Connect Flow Export Module - Output Values

output "s3_bucket_name" {
  description = "Name of the S3 export bucket"
  value       = aws_s3_bucket.export.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 export bucket"
  value       = aws_s3_bucket.export.arn
}

output "lambda_function_arn" {
  description = "ARN of the export Lambda function"
  value       = aws_lambda_function.exporter.arn
}

output "lambda_function_name" {
  description = "Name of the export Lambda function"
  value       = aws_lambda_function.exporter.function_name
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "eventbridge_rule_arns" {
  description = "ARNs of EventBridge rules for CloudTrail events"
  value       = { for k, v in aws_cloudwatch_event_rule.cloudtrail : k => v.arn }
}

output "eventbridge_scheduled_rule_arn" {
  description = "ARN of the scheduled EventBridge rule for rules export"
  value       = try(aws_cloudwatch_event_rule.scheduled_rules[0].arn, null)
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for the export Lambda"
  value       = aws_cloudwatch_log_group.exporter.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for the export Lambda"
  value       = aws_cloudwatch_log_group.exporter.arn
}

output "dlq_arn" {
  description = "ARN of the dead letter queue for failed EventBridge invocations"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}
