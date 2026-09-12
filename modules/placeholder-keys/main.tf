# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# The placeholder-key transform, in one place.
# =============================================================================
#
# An exported template never contains an ARN. Every environment-specific
# reference is a placeholder whose suffix is the base64-encoded resource NAME:
#
#     "QueueId": "${queue_cmV0YWlsLXN1cHBvcnRfZW4}"
#
# `cmV0YWlsLXN1cHBvcnRfZW4` decodes to `retail-support_en`. The name is stable
# across instances; the ARN is not.
#
# Two placeholders exist per resource:
#   <family>_<b64>          the ID the flow needs at runtime
#   display_<family>_<b64>  the friendly label Connect shows in the designer,
#                           stored in the flow's Metadata block
#
# Base64 is used because Terraform variable names cannot contain the characters
# Connect resource names allow — spaces, parentheses, dots. It is made
# identifier-safe by swapping "+"->"-", "/"->"_" and stripping "=" padding.
#
#   *** This must match _encode_name() in the exporter's                    ***
#   *** reference_substitutor.py EXACTLY. Both sides derive keys            ***
#   *** independently and never communicate; if they drift, nothing         ***
#   *** resolves. tests/ asserts both against a shared fixture.            ***
#
# Why this is a module rather than a local in flow-deployer:
#
#   * Terraform has no user-defined functions, so without a module the same
#     nested replace() chain has to be written out once per family — six times
#     in flow-deployer alone, plus again in any root module that adds a family.
#     One typo in one copy produces a key nothing resolves against.
#
#   * It declares no providers and creates no resources, so the encoding can be
#     tested with `command = plan` and no credentials at all. flow-deployer
#     cannot: it holds awscc resources, and the awscc provider calls
#     sts:GetCallerIdentity when it is configured, even for a plan that will
#     create nothing.

variable "resources" {
  description = <<-EOT
    Resources the templates may reference, as { family => { name => id } }.

    `family` is the placeholder prefix and must match what the exporter emits:
    queue, hours_of_operation, data_table, flow_module, contact_flow, prompt.

    Keyed by resource NAME, because the name is what the placeholder encodes.
    Passing IDs keyed by anything else produces keys the exporter never
    generates, and the template then fails to render — loudly, which is the
    intended failure mode.
  EOT
  type        = map(map(string))
  default     = {}
}

variable "display_names" {
  description = <<-EOT
    Families that also need the cosmetic display_<family>_<b64> keys, as
    { family => [name, ...] }.

    Flow Metadata carries friendly names ("Transfer to <queue name>"). These
    resolve to the NAME rather than an ID, so the console shows the right label
    in every instance. Separate from `resources` because some resources need
    only a label — a contact flow referenced by name in Metadata but resolved
    dynamically at contact time, for instance.
  EOT
  type        = map(list(string))
  default     = {}
}

locals {
  # The one transform that matters. Every family goes through this and nothing
  # else does. Change it here and you must change _encode_name() in the exporter.
  #
  # Flattened to a list first because Terraform cannot nest a `for` inside a map
  # key expression across two levels.
  value_pairs = flatten([
    for family, entries in var.resources : [
      for name, id in entries : {
        key   = "${family}_${replace(replace(replace(base64encode(name), "+", "-"), "/", "_"), "=", "")}"
        value = id
      }
    ]
  ])

  display_pairs = flatten([
    for family, names in var.display_names : [
      for name in names : {
        key = "display_${family}_${replace(replace(replace(base64encode(name), "+", "-"), "/", "_"), "=", "")}"
        # Resolves to the name itself: that IS the label.
        value = name
      }
    ]
  ])
}

output "placeholder_map" {
  description = <<-EOT
    Placeholder key -> replacement value, ready to hand to templatefile().
    Includes both the value and display families.
  EOT
  value = merge(
    { for p in local.value_pairs : p.key => p.value },
    { for p in local.display_pairs : p.key => p.value },
  )
}
