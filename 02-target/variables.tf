# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "aws_region" {
  description = "Region for both instances. Must support Amazon Connect data tables."
  type        = string
  default     = "us-east-1"
}

variable "instance_alias_prefix" {
  description = <<-EOT
    Prefix for the Connect instance alias. A random suffix is appended, because
    Connect instance aliases are globally unique across ALL AWS accounts and a
    fixed alias would collide with anyone else running this demo.
  EOT
  type        = string
  default     = "connect-flows-demo-tgt"
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
  default = {
    Project = "connect-flows-as-code-demo"
    Role    = "target-instance"
  }
}
