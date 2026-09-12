# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Outputs merge the console_owned and managed resource sets, so callers do not
# have to know which ownership model was selected. Exactly one of each pair is
# non-empty; see the comment above the resources in main.tf.

output "contact_flow_ids" {
  description = <<-EOT
    Bare flow name -> contact flow ID.

    Derived from the ARN: awscc exposes contact_flow_arn and a composite `id`
    ("instance_arn|contact_flow_arn"), never the bare UUID that a flow reference
    or an aws connect CLI call needs. Same treatment as flow modules.
  EOT
  value = merge(
    { for k, v in awscc_connect_contact_flow.console_owned : k => regex("[^/]+$", v.contact_flow_arn) },
    { for k, v in awscc_connect_contact_flow.managed : k => regex("[^/]+$", v.contact_flow_arn) },
  )
}

output "contact_flow_arns" {
  description = "Bare flow name -> contact flow ARN."
  value = merge(
    { for k, v in awscc_connect_contact_flow.console_owned : k => v.contact_flow_arn },
    { for k, v in awscc_connect_contact_flow.managed : k => v.contact_flow_arn },
  )
}

output "flow_module_ids" {
  description = "Bare module name -> flow module ID."
  value = merge(
    { for k, v in awscc_connect_contact_flow_module.console_owned : k => regex("[^/]+$", v.contact_flow_module_arn) },
    { for k, v in awscc_connect_contact_flow_module.managed : k => regex("[^/]+$", v.contact_flow_module_arn) },
  )
}

output "replacement_map" {
  description = <<-EOT
    The placeholder -> value map used to render CONTACT FLOWS (the superset of
    the two maps). Exposed for debugging: if a template fails to render, diff its
    $${...} references against the keys here to find what is missing.
  EOT
  value       = local.flow_replacement_map
}

output "rendered_flows" {
  description = <<-EOT
    Rendered flow content, keyed by bare name. Used by the walkthrough to diff
    what Terraform seeded against what the exporter later produced.
  EOT
  value       = { for k, v in local.rendered_flows : k => jsonencode(v) }
}
