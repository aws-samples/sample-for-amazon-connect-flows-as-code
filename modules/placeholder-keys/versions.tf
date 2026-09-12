# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

terraform {
  # 1.6 is the real floor: `terraform test` (used by modules/placeholder-keys)
  # arrived in 1.6, and nothing here needs anything newer — terraform_data is
  # 1.4, lifecycle preconditions 1.2, optional() defaults 1.3. Verified on 1.14.1.
  required_version = ">= 1.6.0"

  # No required_providers block, deliberately. This module creates no resources,
  # which is what lets `terraform test` assert the encoding with no AWS
  # credentials — the awscc provider calls sts:GetCallerIdentity as soon as it is
  # configured, even for a plan that will create nothing.
}
