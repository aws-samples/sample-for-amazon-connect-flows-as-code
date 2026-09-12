# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# SOURCE instance: where flows are designed, and where the exporter watches.
# =============================================================================
#
# Apply order and what each piece is for:
#
#   connect-baseline   instance, hours of operation, 2 queues, data table
#                      + columns. Identical NAMES to 02-target, different ARNs.
#
#   flow-deployer      creates the starting flows. console_owns_content = true,
#                      so once created, Terraform stops managing flow content and
#                      a designer's console edit survives the next apply.
#
#   routing-config     writes THIS instance's queue and flow IDs into the data
#                      table, so flows can resolve them per contact instead of
#                      embedding them. Applied last: a row carries the fallback
#                      flow's ID.
#
#   flow-exporter      Lambda + EventBridge + S3. Watches for console saves and
#                      writes portable templates.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

provider "awscc" {
  region = var.aws_region
}

# Connect instance aliases are globally unique across all AWS accounts, so a
# fixed alias would collide with anyone else running this demo.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

module "baseline" {
  source = "../modules/connect-baseline"

  instance_alias = "${var.instance_alias_prefix}-${random_string.suffix.result}"
  tags           = var.tags
}

# -----------------------------------------------------------------------------
# Starting flows
# -----------------------------------------------------------------------------
#
# `gui-` prefix so the exporter picks them up. Names are BARE here — flow-deployer
# adds the prefix — because the bare name is what the exporter encodes into
# placeholders and writes into the S3 key.
#
# retail-support_main deliberately routes to the WRONG queue. Re-pointing it in
# the console is the reader's one manual step, and the export then captures a
# change Terraform did not make.

module "flows" {
  source = "../modules/flow-deployer"

  instance_arn = module.baseline.instance_arn
  template_dir = "${path.module}/flows"
  name_prefix  = var.export_name_prefix

  # The console owns flow content in this instance. See the module for why this
  # cannot be a simple conditional on ignore_changes.
  console_owns_content = true

  queue_ids              = module.baseline.queue_ids
  hours_of_operation_ids = { (module.baseline.hours_of_operation_name) = module.baseline.hours_of_operation_id }
  data_table_ids         = { (module.baseline.data_table_name) = module.baseline.data_table_id }

  contact_flow_module_definitions = {
    "global_read_prompt_from_datatable" = {
      template    = "global_read_prompt_from_datatable.json.tpl"
      description = "Reads caller-facing copy from the routing_config data table."
    }
  }

  contact_flow_definitions = {
    "retail-support_main" = {
      template    = "retail-support_main.json.tpl"
      description = "Main inbound flow. Looks up routing config, then transfers to the working queue."
    }
    "retail-support_fallback" = {
      template    = "retail-support_fallback.json.tpl"
      description = "Fallback flow, reached dynamically when the main flow errors."
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Routing configuration: this instance's IDs, read by flows at contact time
# -----------------------------------------------------------------------------

module "routing_config" {
  source = "../modules/routing-config"

  instance_arn             = module.baseline.instance_arn
  data_table_arn           = module.baseline.data_table_arn
  data_table_attribute_ids = module.baseline.data_table_attribute_ids

  records = {
    retail = {
      ConfigKey = "retail"

      # The queue the flow SHOULD end up using. Note the seeded flow points at
      # retail-priority_en instead; the reader fixes that in the console.
      QueueId = module.baseline.queue_ids["retail-support_en"]

      # Resolved at contact time, which is what removes the flow -> flow
      # dependency cycle and the need for a second apply.
      FallbackFlowId = module.flows.contact_flow_ids["retail-support_fallback"]

      GreetingText = "Thanks for calling AnyCompany retail support."
    }
  }
}

# -----------------------------------------------------------------------------
# Export automation
# -----------------------------------------------------------------------------

module "exporter" {
  source = "../modules/flow-exporter"

  connect_instance_id = module.baseline.instance_id
  s3_key_prefix       = var.s3_key_prefix
  resource_types      = var.resource_types
  export_name_prefix  = var.export_name_prefix

  # Event-driven. No CloudTrail trail is created: mutating management events
  # reach EventBridge by default. See the README.
  enable_cloudtrail_triggers = true

  # Nothing in this demo exports Contact Lens rules, which is the only thing the
  # scheduled path is for.
  enable_scheduled_export = false

  tags = var.tags
}
