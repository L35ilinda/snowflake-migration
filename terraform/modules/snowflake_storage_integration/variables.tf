variable "name" {
  type        = string
  description = "Snowflake storage integration name (UPPERCASE in Snowflake; Terraform will uppercase)."
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID that owns the storage account."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the Azure storage account (not the container)."
}

variable "allowed_containers" {
  type        = list(string)
  description = "Blob container names that the integration may access. Each becomes an entry in STORAGE_ALLOWED_LOCATIONS."
}

variable "environment" {
  type        = string
  description = "Environment name, used only in the object comment."
}
