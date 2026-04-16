variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group containing the storage account."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the existing Azure storage account."
}

variable "containers" {
  type = map(object({
    access_type = optional(string, "private")
  }))
  description = "Map of container name -> config. access_type defaults to 'private'."

  validation {
    condition     = alltrue([for name, _ in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name))])
    error_message = "Container names must be 3-63 chars, lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}