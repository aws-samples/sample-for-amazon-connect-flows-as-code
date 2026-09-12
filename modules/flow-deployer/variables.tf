# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Every resource here is awscc, and Cloud Control addresses Connect children by
# instance ARN, so no instance ID input is needed.
variable "instance_arn" {
  description = "Amazon Connect instance ARN."
  type        = string
}

variable "console_owns_content" {
  description = <<-EOT
    Who owns flow content after creation.

    true  — the console wins. Flows are created with `ignore_changes = [content]`,
            so a designer's edit survives the next apply. Use this for the SOURCE
            instance, which is a design surface.

    false — Terraform wins. A new template updates the deployed flow, which is
            what promotion means. Use this for the TARGET instance.

    Terraform's lifecycle block cannot take a variable, so this selects between
    two otherwise-identical resource blocks rather than toggling ignore_changes.
  EOT
  type        = bool
}

variable "template_dir" {
  description = "Directory holding the .json.tpl templates to render."
  type        = string
}

variable "name_prefix" {
  description = <<-EOT
    Prefix applied to created flow and module names, e.g. "gui-". The exporter
    only exports resources whose name starts with its own export_name_prefix and
    strips it from the output filename, so the two must agree in the source
    instance. Usually empty in the target, where nothing is exported.
  EOT
  type        = string
  default     = ""
}

# --- Definitions -------------------------------------------------------------
#
# Keyed by the resource's BARE name — the name without name_prefix, which is
# also the name the exporter writes into the S3 key and encodes into
# placeholders. Keeping the key bare means the same definition map works whether
# or not a prefix is applied.

variable "contact_flow_definitions" {
  description = <<-EOT
    Contact flows to deploy, as { bare_name => { template, type?, state?,
    description? } }. `template` is a filename relative to template_dir.

    `state` is ACTIVE or ARCHIVED — the flow's lifecycle state, not its publish
    status. Neither provider exposes Status (SAVED vs PUBLISHED).
  EOT
  type = map(object({
    template    = string
    type        = optional(string, "CONTACT_FLOW")
    state       = optional(string, "ACTIVE")
    description = optional(string)
  }))
  default = {}
}

variable "contact_flow_module_definitions" {
  description = <<-EOT
    Flow modules to deploy, as { bare_name => { template, state?, description?,
    settings? } }. `settings` is the module's input/output parameter and custom
    branch schema; it is declared here because DescribeContactFlowModule does not
    return it, so the exporter cannot carry it in the template.
  EOT
  type = map(object({
    template    = string
    state       = optional(string, "ACTIVE")
    description = optional(string)
    settings    = optional(any)
  }))
  default = {}
}

# --- Resources the templates may reference -----------------------------------
#
# Every map is keyed by resource NAME, because the placeholder key is derived
# from the name. Passing IDs keyed by anything else would produce keys the
# exporter never generates.

variable "queue_ids" {
  description = "Queue name -> queue ID. Flow blocks store queues by ID."
  type        = map(string)
  default     = {}
}

variable "hours_of_operation_ids" {
  description = "Hours of operation name -> ID."
  type        = map(string)
  default     = {}
}

variable "data_table_ids" {
  description = "Data table name -> table ID. A Data table block stores the table by ID."
  type        = map(string)
  default     = {}
}

variable "extra_replacements" {
  description = <<-EOT
    Additional placeholder key -> value pairs, merged last so they win. An escape
    hatch for a reference type this module does not model yet; prefer adding a
    proper family over using it.
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default     = {}
}
