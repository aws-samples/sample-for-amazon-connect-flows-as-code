# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

terraform {
  # 1.6 is the real floor: `terraform test` (used by modules/placeholder-keys)
  # arrived in 1.6, and nothing here needs anything newer — terraform_data is
  # 1.4, lifecycle preconditions 1.2, optional() defaults 1.3. Verified on 1.14.1.
  required_version = ">= 1.6.0"

  required_providers {
    # awscc only. Every resource this module creates — contact flows, flow
    # modules and their versions — is managed through AWS Cloud Control, so new
    # Connect features are reachable as soon as CloudFormation supports them
    # rather than when the AWS provider catches up. Data tables and flow modules
    # have no aws-provider equivalent at all.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.7"
    }
  }
}
