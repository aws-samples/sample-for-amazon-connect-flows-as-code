# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Two-instance flow promotion demo: `01-source` and `02-target` root modules
  sharing the same `connect-baseline` and `flow-deployer` modules.
- Event-driven exporter (AWS Lambda + Amazon EventBridge + Amazon S3) that
  rewrites environment-specific references into portable placeholders.
- Cross-language encoding contract test, asserted from both Python
  (`tests/test_encoding.py`) and Terraform
  (`modules/placeholder-keys/tests/`) against one shared fixture.
- `.pylintrc` documenting the linting exceptions and their reasons.

### Changed
- Contact flows and flow modules are deployed with the `awscc` provider rather
  than `aws`, so newly released Amazon Connect Customer features are reachable
  as soon as AWS CloudFormation supports them.
- `required_version` relaxed to `>= 1.6.0`, the true floor (`terraform test`).

### Removed
- The DynamoDB resource registry carried over from the production
  implementation. Nothing in the exporter reads DynamoDB, and this sample
  resolves every placeholder from module outputs, so the table would have been
  written to and never read. See the README for the full rationale.
- `data_tables` from the exporter's resource types: that exporter is a stub
  not implemented and exported nothing while logging a misleading warning.
