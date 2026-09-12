# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "instance_id" {
  description = "Source instance ID. Needed for the aws connect CLI calls in the walkthrough."
  value       = module.baseline.instance_id
}

output "instance_alias" {
  description = "Source instance alias. Log in at https://<alias>.my.connect.aws/"
  value       = module.baseline.instance_alias
}

output "console_url" {
  description = "Direct link to the flows list in this instance's console."
  value       = "https://${module.baseline.instance_alias}.my.connect.aws/contact-flows"
}

output "export_bucket" {
  description = "Bucket the exporter writes portable templates to."
  value       = module.exporter.s3_bucket_name
}

output "exporter_function_name" {
  description = "Exporter Lambda name, for logs and for the manual full-export invoke."
  value       = module.exporter.lambda_function_name
}

output "queue_ids" {
  description = "Queue name -> ID in this instance. Compare against 02-target to see the ARNs differ."
  value       = module.baseline.queue_ids
}

output "contact_flow_ids" {
  description = "Bare flow name -> ID in this instance."
  value       = module.flows.contact_flow_ids
}

output "rendered_flows" {
  description = <<-EOT
    What Terraform seeded, keyed by bare flow name. Diff this against the exported
    template to see exactly what the console change produced:

      terraform output -raw rendered_flows | jq -r '."retail-support_main"' | jq .
  EOT
  value       = module.flows.rendered_flows
}

output "next_steps" {
  description = "What to do after this applies."
  value       = <<-EOT

    Source instance is up: ${module.baseline.instance_alias}

    1. Open the flow in the console and re-point one block:
         https://${module.baseline.instance_alias}.my.connect.aws/contact-flows
         ${var.export_name_prefix}retail-support_main
           -> Set working queue block
           -> change the queue to retail-support_en
           -> Save, then Publish

    2. Confirm the exporter fired (CloudTrail delivery takes a few minutes):
         aws logs tail /aws/lambda/${module.exporter.lambda_function_name} --since 10m --follow

    3. Look at the portable template it produced:
         aws s3 ls s3://${module.exporter.s3_bucket_name}/${var.s3_key_prefix}/contact_flows/
         aws s3 cp s3://${module.exporter.s3_bucket_name}/${var.s3_key_prefix}/contact_flows/retail-support_main.json.tpl -

       Expect $${queue_...} and $${data_table_...} placeholders, and no ARNs.

    If nothing arrives in step 2, prove the Lambda independently of the event
    plumbing with a full export:
         aws lambda invoke --function-name ${module.exporter.lambda_function_name} \
           --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout

  EOT
}
