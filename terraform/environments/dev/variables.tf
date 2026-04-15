variable "environment" {
  type    = string
  default = "dev"
}

# ---- Azure ----
variable "azure_subscription_id" { type = string }
variable "azure_tenant_id" { type = string }
variable "azure_resource_group_name" { type = string }
variable "azure_storage_account_name" { type = string }
variable "azure_storage_container_company_01" { type = string }
variable "azure_storage_container_company_02" { type = string }
variable "azure_storage_container_company_03" { type = string }

# ---- Snowflake ----
variable "snowflake_organization_name" { type = string }
variable "snowflake_account_name" { type = string }
variable "snowflake_user" { type = string }
variable "snowflake_role" {
  type    = string
  default = "ACCOUNTADMIN"
}

variable "snowflake_private_key_path" {
  type        = string
  description = "Absolute path to the PKCS#8 RSA private key used for SNOWFLAKE_JWT auth. Must live outside the repo. See ADR-0005."
}
