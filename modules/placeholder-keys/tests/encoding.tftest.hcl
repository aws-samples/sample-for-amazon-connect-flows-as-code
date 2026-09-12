# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# The Terraform half of the placeholder-encoding contract.
#
#   cd modules/placeholder-keys && terraform test
#
# The Python half is tests/test_encoding.py. Both read
# tests/encoding-fixture.json, so a change to either implementation fails one of
# them. If they ever disagree in a real deployment, no placeholder resolves and
# templatefile() aborts the apply — the right failure, but only after a pipeline
# has already run.
#
# command = plan, and this module declares no providers and creates no resources,
# so the test needs no AWS credentials at all.

run "encoding_matches_shared_fixture" {
  command = plan

  module {
    source = "./tests/encoding-test"
  }

  assert {
    condition     = output.fixture_case_count > 0
    error_message = "Fixture is empty or unreadable — the test would pass vacuously."
  }

  assert {
    condition     = output.actual_keys == output.expected_keys
    error_message = <<-EOT
      The placeholder encoding no longer matches the shared fixture.

      expected: ${join(", ", output.expected_keys)}
      actual:   ${join(", ", output.actual_keys)}

      The transform must be base64(name), then "+"->"-", "/"->"_", strip "=".
      It has to stay identical to _encode_name() in the exporter's
      reference_substitutor.py. If the change is deliberate, update the fixture
      AND both implementations together.
    EOT
  }

  assert {
    condition     = output.display_values_are_names
    error_message = <<-EOT
      A display_* placeholder does not resolve to the resource name.

      Display keys populate the flow's Metadata block, which is what the console
      renders as a block label. Resolving one to an ID deploys a flow that works
      and reads wrong in the designer — nothing at apply time would catch it.
    EOT
  }
}
