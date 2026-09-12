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
  default     = "connect-flows-demo-src"
}

variable "export_name_prefix" {
  description = <<-EOT
    Only flows whose name starts with this prefix are exported, and the prefix is
    stripped from the S3 key. It lets a designer experiment in the console without
    polluting the repo: name a flow `scratch-foo` and the exporter ignores it.

    Must match the name_prefix that flow-deployer applies when it creates flows,
    or the exporter will skip the very flows this demo is about.
  EOT
  type        = string
  default     = "gui-"
}

variable "s3_key_prefix" {
  description = <<-EOT
    Prefix for exported S3 keys, conventionally the environment name. Produces
    keys like `source/contact_flows/retail-support_main.json.tpl`.
  EOT
  type        = string
  default     = "source"
}

variable "resource_types" {
  description = <<-EOT
    Resource types the exporter writes to S3.

    Deliberately does NOT include "data_tables". DataTableExporter is a stub
    not implemented — its own docstring says so, `_list_resources()` returns
    an empty list and `_describe_resource()` makes no API call — so enabling it
    exports nothing and logs "Data table listing not yet fully implemented" on
    every run.

    The data table still works in this demo, because it is not exported at all:
    connect-baseline creates it in BOTH instances, and the exporter's
    $${data_table_<b64>} placeholder resolves from _build_data_table_mapping(),
    which runs unconditionally and does not consult this list.

    The exporter also supports views, workspaces, rules and evaluation_forms.
    Those are outside this demo's scope; "workspaces" is also a stub.
  EOT
  type        = list(string)
  default     = ["contact_flows", "contact_flow_modules"]
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
  default = {
    Project = "connect-flows-as-code-demo"
    Role    = "source-instance"
  }
}
