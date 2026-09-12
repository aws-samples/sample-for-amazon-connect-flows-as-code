#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Assert the exporter's placeholder encoding matches the shared fixture.

Run:  python3 tests/test_encoding.py

The Terraform side of the same contract is asserted by
tests/encoding.tftest.hcl, which reads the same fixture. Both must pass.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent

# Import the real implementation rather than reimplementing it here — the point
# of the test is that THIS function agrees with Terraform.
sys.path.insert(0, str(REPO / "modules/flow-exporter/lambda/exporter"))
# pylint: disable=wrong-import-position  # sys.path must be set before this import
from transformers.reference_substitutor import ReferenceSubstitutor  # noqa: E402


def main() -> int:
    """Assert the exporter's encoding matches the shared fixture."""
    cases = json.loads((HERE / "encoding-fixture.json").read_text())["cases"]

    failures = []
    for name, expected in sorted(cases.items()):
        actual = ReferenceSubstitutor._encode_name(  # pylint: disable=protected-access
            name)
        status = "ok" if actual == expected else "FAIL"
        if actual != expected:
            failures.append((name, expected, actual))
        print(f"  {status:<4} {name:<36} {actual}")

    print()
    if failures:
        print(f"{len(failures)} mismatch(es) — the exporter and the fixture disagree:")
        for name, expected, actual in failures:
            print(f"  {name}\n    fixture: {expected}\n    actual:  {actual}")
        print(
            "\nIf the encoding changed deliberately, update the fixture AND confirm\n"
            "tests/encoding.tftest.hcl still passes. Changing only one side breaks\n"
            "every placeholder at apply time."
        )
        return 1

    print(f"All {len(cases)} cases match. Encoding contract holds on the Python side.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
