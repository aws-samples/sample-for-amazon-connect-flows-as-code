## What does this change?

<!-- A short description, and the issue it closes if there is one. -->

## Checks

- [ ] `terraform fmt -recursive .` is clean
- [ ] `python3 tests/test_encoding.py` passes
- [ ] `cd modules/placeholder-keys && terraform test` passes
- [ ] `pylint` run against `modules/flow-exporter/lambda/exporter`

If this changes the placeholder encoding, it must change on **both** sides —
the exporter's `_encode_name()` and `modules/placeholder-keys` — and
`tests/encoding-fixture.json` must be updated. The two sides derive keys
independently and never communicate, so a one-sided change means no placeholder
resolves, and it fails at apply time rather than in review.

## Licence

By submitting this pull request I confirm that my contribution is made under the
terms of the MIT-0 licence.
