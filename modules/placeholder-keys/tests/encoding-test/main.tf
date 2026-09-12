# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Wrapper that exercises the real encoding against the shared fixture.
# =============================================================================
#
# Terraform has no user-defined functions, so the transform cannot be called
# directly from a test — the only way to observe it is to feed the module
# resource NAMES and read the placeholder keys back out. This wrapper does that
# against the module that actually renders templates, not a copy of it that could
# drift.
#
# Expected values come from tests/encoding-fixture.json, the same file
# tests/test_encoding.py reads.

locals {
  fixture = jsondecode(file("${path.module}/../../../../tests/encoding-fixture.json")).cases

  # Every family goes through the identical transform, so driving one family
  # proves it for all of them. The value is irrelevant to the encoding.
  fake_id = "00000000-0000-0000-0000-000000000000"
}

module "keys" {
  source = "../.."

  resources     = { queue = { for name, _ in local.fixture : name => local.fake_id } }
  display_names = { queue = keys(local.fixture) }
}

output "expected_keys" {
  description = "Placeholder keys the fixture says the module must produce, value and display families."
  value = sort(concat(
    [for name, b64 in local.fixture : "queue_${b64}"],
    [for name, b64 in local.fixture : "display_queue_${b64}"],
  ))
}

output "actual_keys" {
  description = "Placeholder keys the module actually produced."
  value       = sort(keys(module.keys.placeholder_map))
}

output "display_values_are_names" {
  description = <<-EOT
    True when every display_* key resolves to the resource NAME. A display key
    that resolved to an ID would deploy a working flow that shows the wrong label
    in the designer — a failure no apply-time error would catch.
  EOT
  value = alltrue([
    for name, b64 in local.fixture :
    module.keys.placeholder_map["display_queue_${b64}"] == name
  ])
}

output "fixture_case_count" {
  description = "Guards against an empty or unreadable fixture silently passing the test."
  value       = length(local.fixture)
}
