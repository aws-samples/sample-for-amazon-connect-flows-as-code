# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# TARGET instance: where promoted flows land.
# =============================================================================
#
# Compare this file with 01-source/main.tf. The two are almost the same, and the
# three places they differ are the entire argument of the demo:
#
#   1. flows/ holds templates the EXPORTER produced, copied out of the source
#      instance's bucket. 01-source/flows/ holds templates written by hand.
#
#   2. console_owns_content = FALSE. Terraform owns flow content here, so a new
#      template updates the deployed flow. That is what promotion means. In the
#      source instance the console wins instead.
#
#   3. There is no exporter. Nothing is authored here, so there is nothing to
#      export.
#
# Everything else — the same connect-baseline module, the same flow-deployer, the
# same routing-config — is deliberately identical. Baseline creates resources
# with the SAME NAMES as the source instance and necessarily DIFFERENT ARNs, and
# flow-deployer rebuilds each placeholder key from the names it finds here. That
# is why one template deploys to both instances with no editing.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

provider "awscc" {
  region = var.aws_region
}

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
# Promoted flows
# -----------------------------------------------------------------------------
#
# Discovered from disk rather than listed by hand. Whatever the reader copied out
# of the export bucket gets deployed, so adding a flow to the demo is a file copy
# and not a Terraform edit — the same property the production accelerator relies
# on when a designer adds a flow that no one has written HCL for.
#
# The exporter names files after the resource's BARE name (prefix stripped), so
# trimming ".json.tpl" recovers the key flow-deployer wants.

locals {
  # fileset() returns an empty set for a directory that does not exist rather than
  # failing, and flows/ and flow-modules/ are gitignored — a fresh clone has
  # neither. So "no templates" is the normal state before step 5 of the README,
  # and terraform_data.templates_present below turns it into a readable error
  # instead of an "Invalid index" from routing_config.
  flow_templates        = fileset("${path.module}/flows", "*.json.tpl")
  flow_module_templates = fileset("${path.module}/flow-modules", "*.json.tpl")

  contact_flow_definitions = {
    for f in local.flow_templates :
    trimsuffix(f, ".json.tpl") => {
      template    = f
      description = "Promoted from the source instance. Rendered from ${f}."
    }
  }

  contact_flow_module_definitions = {
    for f in local.flow_module_templates :
    trimsuffix(f, ".json.tpl") => {
      template    = f
      description = "Promoted from the source instance. Rendered from ${f}."
    }
  }
}

# Guard: promotion needs something to promote.
#
# Without this, applying before the templates are copied fails deep inside
# routing_config with "Invalid index ... retail-support_fallback", which says
# nothing about the actual mistake. Creates no infrastructure.
resource "terraform_data" "templates_present" {
  input = {
    flows        = length(local.flow_templates)
    flow_modules = length(local.flow_module_templates)
  }

  lifecycle {
    precondition {
      condition     = length(local.flow_templates) > 0 && length(local.flow_module_templates) > 0
      error_message = <<-EOT
        No templates found in 02-target/flows/ and/or 02-target/flow-modules/.

        These are produced by the exporter in the source instance and are
        deliberately not committed, so a fresh clone starts empty.

        Note that the exporter is event-driven: it exports what CHANGED. Editing
        the main flow in the console exports contact flows but NOT the flow
        module, which leaves flow-modules/ empty and the flow templates
        referencing a $${flow_module_<b64>} placeholder with nothing to resolve
        it to. Force a full export first — an empty payload means "everything":

          cd ../01-source
          aws lambda invoke --function-name $(terraform output -raw exporter_function_name) \
            --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout
          BUCKET=$(terraform output -raw export_bucket)

          cd ../02-target && mkdir -p flows flow-modules
          aws s3 cp "s3://$BUCKET/source/contact_flows/"        flows/        --recursive
          aws s3 cp "s3://$BUCKET/source/contact_flow_modules/" flow-modules/ --recursive
      EOT
    }
  }
}

# Flow modules first: a contact flow's InvokeFlowModule block needs the module ID
# substituted at deploy time, so the modules have to exist before the flows are
# rendered. flow-deployer handles that ordering internally, but it needs the
# templates from a different directory, hence two calls to the same module.
module "flow_modules" {
  source = "../modules/flow-deployer"

  instance_arn = module.baseline.instance_arn
  template_dir = "${path.module}/flow-modules"

  # Terraform owns content here. This is the line that makes it a promotion
  # target rather than a design surface.
  console_owns_content = false

  queue_ids              = module.baseline.queue_ids
  hours_of_operation_ids = { (module.baseline.hours_of_operation_name) = module.baseline.hours_of_operation_id }
  data_table_ids         = { (module.baseline.data_table_name) = module.baseline.data_table_id }

  contact_flow_module_definitions = local.contact_flow_module_definitions

  tags = var.tags
}

module "flows" {
  source = "../modules/flow-deployer"

  instance_arn = module.baseline.instance_arn
  template_dir = "${path.module}/flows"

  console_owns_content = false

  queue_ids              = module.baseline.queue_ids
  hours_of_operation_ids = { (module.baseline.hours_of_operation_name) = module.baseline.hours_of_operation_id }
  data_table_ids         = { (module.baseline.data_table_name) = module.baseline.data_table_id }

  contact_flow_definitions = local.contact_flow_definitions

  # The flow templates carry ${flow_module_<b64>} placeholders, and the modules
  # come from the other flow-deployer call above. Passing their keys in as extra
  # replacements is what lets the two calls cooperate without a cycle.
  #
  # Built with the same placeholder-keys module the deployer uses internally, so
  # there is exactly one definition of the transform in the repo.
  extra_replacements = module.promoted_module_keys.placeholder_map

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Routing configuration: THIS instance's IDs
# -----------------------------------------------------------------------------
#
# Identical in shape to the source instance, and that is the point. The promoted
# flow reads $.DataTables.RoutingLookup.QueueId at contact time; this is where
# that value comes from, and it is a target-instance ID.

module "routing_config" {
  source = "../modules/routing-config"

  instance_arn             = module.baseline.instance_arn
  data_table_arn           = module.baseline.data_table_arn
  data_table_attribute_ids = module.baseline.data_table_attribute_ids

  records = {
    retail = {
      ConfigKey      = "retail"
      QueueId        = module.baseline.queue_ids["retail-support_en"]
      FallbackFlowId = module.flows.contact_flow_ids["retail-support_fallback"]
      GreetingText   = "Thanks for calling AnyCompany retail support."
    }
  }
}

# Keys for the promoted flow modules, so the flow templates can resolve
# ${flow_module_<b64>}. Declared here rather than inside flow-deployer because
# the modules and the flows are deployed by two separate calls to it.
module "promoted_module_keys" {
  source = "../modules/placeholder-keys"

  resources     = { flow_module = module.flow_modules.flow_module_ids }
  display_names = { flow_module = keys(module.flow_modules.flow_module_ids) }
}
