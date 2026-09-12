# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "instance_id" {
  description = "Target instance ID. Needed for the aws connect CLI calls that verify the promotion."
  value       = module.baseline.instance_id
}

output "instance_alias" {
  description = "Target instance alias. Log in at https://<alias>.my.connect.aws/"
  value       = module.baseline.instance_alias
}

output "console_url" {
  description = "Direct link to the flows list in this instance's console."
  value       = "https://${module.baseline.instance_alias}.my.connect.aws/contact-flows"
}

output "queue_ids" {
  description = <<-EOT
    Queue name -> ID in this instance. The names match 01-source exactly and the
    IDs cannot match, which is the condition the whole pattern exists to survive.
  EOT
  value       = module.baseline.queue_ids
}

output "contact_flow_ids" {
  description = "Bare flow name -> ID in this instance."
  value       = module.flows.contact_flow_ids
}

output "flow_module_ids" {
  description = "Bare module name -> ID in this instance."
  value       = module.flow_modules.flow_module_ids
}

output "replacement_map" {
  description = <<-EOT
    Placeholder key -> value actually used to render the promoted flows. Read this
    when a template fails to render: the missing key is the reference the target
    instance does not have a resource for.
  EOT
  value       = module.flows.replacement_map
}

output "verify" {
  description = "How to confirm the promotion landed correctly."
  value       = <<-EOT

    Target instance is up: ${module.baseline.instance_alias}

    Dump a promoted flow and confirm every ID belongs to THIS instance:

      aws connect describe-contact-flow \
        --instance-id ${module.baseline.instance_id} \
        --contact-flow-id ${try(module.flows.contact_flow_ids["retail-support_main"], "<flow-id>")} \
        --query 'ContactFlow.Content' --output text | jq .

    Expect:
      * the data table ID to be this instance's routing_config
      * the InvokeFlowModule ID to be this instance's flow module
      * the queue to be this instance's retail-support_en, NOT the source's
      * TransferToFlow to still read $.DataTables.RoutingLookup.FallbackFlowId
      * no $${...} placeholders and no source-instance IDs anywhere

    Side-by-side with the source instance:

      diff <(cd ../01-source && terraform output -json queue_ids) \
           <(terraform output -json queue_ids)

    Same names, different IDs. That is the promotion working.

  EOT
}
