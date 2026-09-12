# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Exporter Lambda, packaged from source at apply time.
# =============================================================================
#
# The production version of this module points `filename` at a pre-built
# `dummy.zip` and carries `ignore_changes = [filename, source_code_hash]`,
# because its real artifact is built and pushed by a CI pipeline. That is fine
# there and useless here: with no pipeline, Terraform would create a Lambda
# containing nothing.
#
# So this build is self-contained. `terraform apply` produces a working Lambda
# with no prior steps:
#
#   1. pip install boto3 into a build directory   (terraform_data + local-exec)
#   2. copy the exporter source alongside it
#   3. zip the result                             (archive_file)
#
# boto3 has to be bundled rather than relying on the runtime's copy: the Connect
# data tables API needs boto3 >= 1.35, and the version baked into a Lambda
# runtime is whatever it shipped with. Pinning here also keeps the artifact
# reproducible.
#
# Requires python3 and pip on the machine running Terraform. That is already a
# prerequisite for reading the exporter source, and it matches how the wider
# accelerator builds its TypeScript Lambdas (terraform_data + npm ci).

locals {
  lambda_src_dir   = "${path.module}/lambda/exporter"
  lambda_build_dir = "${path.module}/.build/exporter"
  lambda_zip_path  = "${path.module}/.build/exporter.zip"

  # Hash every source file so the build re-runs when any of them changes.
  # fileset+filemd5 rather than a directory hash, because Terraform has no
  # built-in recursive directory hash.
  lambda_src_hash = sha256(join("", [
    for f in sort(fileset(local.lambda_src_dir, "**/*.py")) :
    filemd5("${local.lambda_src_dir}/${f}")
  ]))
}

resource "terraform_data" "lambda_build" {
  # Rebuild when the source changes or the pinned boto3 version moves.
  triggers_replace = {
    src_hash      = local.lambda_src_hash
    boto3_version = var.boto3_version
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      BUILD_DIR="${abspath(local.lambda_build_dir)}"
      SRC_DIR="${abspath(local.lambda_src_dir)}"

      rm -rf "$BUILD_DIR"
      mkdir -p "$BUILD_DIR"

      # Dependencies first, then source on top, so a name collision surfaces as
      # the source winning rather than being silently overwritten.
      python3 -m pip install --quiet --no-cache-dir \
        --only-binary=:all: --platform manylinux2014_x86_64 \
        --target "$BUILD_DIR" "boto3==${var.boto3_version}"

      cp -R "$SRC_DIR"/. "$BUILD_DIR"/

      # Trim what does not need to ship. botocore carries service definitions for
      # every AWS API, which is most of the artifact's size.
      #
      # The keep-list must cover every service the exporter builds a client for
      # (grep for `client(` under lambda/exporter). Dropping one it does use is
      # not a hard failure — reference_substitutor logs a warning and carries on
      # with an incomplete mapping — so a missing entry shows up as a placeholder
      # that silently never resolves. lexv2-models is the easy one to forget.
      find "$BUILD_DIR/botocore/data" -mindepth 1 -maxdepth 1 -type d \
        ! -name 'connect' ! -name 's3' \
        ! -name 'chime-sdk-voice' ! -name 'lexv2-models' \
        -exec rm -rf {} + 2>/dev/null || true
      find "$BUILD_DIR" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
      find "$BUILD_DIR" -type d -name '*.dist-info' -exec rm -rf {} + 2>/dev/null || true

      test -f "$BUILD_DIR/handler.py" || { echo "handler.py missing from build"; exit 1; }
    EOT
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = local.lambda_zip_path

  depends_on = [terraform_data.lambda_build]
}

resource "aws_cloudwatch_log_group" "exporter" {
  #checkov:skip=CKV_AWS_158:A customer-managed KMS key on the log group costs more than the logs are worth. Nothing sensitive is logged — see the LOG_LEVEL note in SECURITY.md.
  name              = local.exporter_log_group_name
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Name = local.exporter_log_group_name })
}

resource "aws_lambda_function" "exporter" {
  #checkov:skip=CKV_AWS_117:A VPC would require NAT or interface endpoints for the Connect and S3 APIs, adding hourly cost and a networking layer that has nothing to do with what this sample teaches. The function calls only AWS public APIs and holds no inbound surface.
  #checkov:skip=CKV_AWS_173:Environment variables hold a bucket name, an instance ID and a log level. None is a secret, so a KMS key would encrypt nothing worth encrypting. Anything secret would belong in Secrets Manager instead.
  #checkov:skip=CKV_AWS_272:Code signing requires a Signer profile and a signing step in the build. The artifact here is built locally by terraform_data at apply time, so a reader would have to create signing infrastructure before their first apply.
  function_name = "${local.name_prefix}-exporter"
  description   = "Exports Amazon Connect resources to S3, substituting ARNs and IDs for portable placeholders"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "python3.12"
  handler = "handler.handler"

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout
  role        = aws_iam_role.lambda_execution.arn

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  # Asynchronous invocations that fail AFTER EventBridge has delivered them land
  # here. The EventBridge targets have their own dead_letter_config on the same
  # queue, but that only covers failures to DELIVER; without this block, a Lambda
  # that is invoked and then errors is lost silently.
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  # Tracing costs a few cents at this volume and makes the CloudTrail ->
  # EventBridge -> Lambda path visible end to end, which is exactly the hop
  # readers most often need to debug.
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CONNECT_INSTANCE_ID       = var.connect_instance_id
      S3_BUCKET                 = aws_s3_bucket.export.bucket
      S3_KEY_PREFIX             = var.s3_key_prefix
      RESOURCE_TYPES            = join(",", var.resource_types)
      EXPORT_ALL_VERSIONS       = tostring(var.export_all_versions)
      EXPORT_DATA_TABLE_RECORDS = tostring(var.export_data_table_records)
      LOG_LEVEL                 = var.log_level
      ENVIRONMENT               = local.environment
      EXPORT_NAME_PREFIX        = var.export_name_prefix
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.exporter,
    aws_iam_role_policy_attachment.cloudwatch_logs,
  ]

  tags = merge(var.tags, { Name = "${local.name_prefix}-exporter" })
}

# One permission per rule, each scoped to that rule's ARN.
#
# source_account alone is not sufficient: it lets ANY EventBridge rule in the
# account invoke this function, so any principal who can create a rule can drive
# the exporter. source_arn closes that — the classic confused-deputy protection.
# A single aws_lambda_permission cannot carry several source ARNs, hence for_each
# over the rules rather than one broad grant.
resource "aws_lambda_permission" "eventbridge_cloudtrail" {
  for_each = local.enabled_cloudtrail_rules

  statement_id   = "AllowEventBridgeInvoke-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.exporter.function_name
  principal      = "events.amazonaws.com"
  source_account = local.account_id
  source_arn     = aws_cloudwatch_event_rule.cloudtrail[each.key].arn
}

# count, not for_each, to mirror aws_cloudwatch_event_rule.scheduled_rules.
resource "aws_lambda_permission" "eventbridge_scheduled" {
  count = length(aws_cloudwatch_event_rule.scheduled_rules)

  statement_id   = "AllowEventBridgeInvokeScheduled-${count.index}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.exporter.function_name
  principal      = "events.amazonaws.com"
  source_account = local.account_id
  source_arn     = aws_cloudwatch_event_rule.scheduled_rules[count.index].arn
}
