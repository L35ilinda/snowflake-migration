variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group containing the storage account."
}

variable "storage_account_name" {
  type        = string
  description = "Existing storage account where the tfstate container will be created."
}

variable "tfstate_container_name" {
  type        = string
  default     = "tfstate"
  description = "Name of the blob container for Terraform remote state."
}
