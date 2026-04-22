variable "environment" {
  type    = string
  default = "dev"
}

# ---- Azure ----
variable "azure_subscription_id" { type = string }
variable "azure_tenant_id" { type = string }
variable "azure_resource_group_name" { type = string }
variable "azure_storage_account_name" { type = string }
variable "azure_storage_container_main_book" { type = string }
variable "azure_storage_container_indigo_insurance" { type = string }
variable "azure_storage_container_horizon_assurance" { type = string }

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

# ---- CI service user ----
# Public key for the CI_SVC user (used by GitHub Actions). Register the
# matching private key as a GitHub repository secret. See ADR-0009.
variable "ci_svc_public_key_path" {
  type        = string
  description = "Absolute path to the CI_SVC public key file (PEM, no PEM headers). Must live outside the repo."
}

# ---- Airbyte service user ----
# Public key for the AIRBYTE_SVC user (used by self-hosted Airbyte to write
# into RAW_OPS). Configure the matching private key as the destination
# credential in the Airbyte UI. See ADR-0013.
variable "airbyte_svc_public_key_path" {
  type        = string
  description = "Absolute path to the AIRBYTE_SVC public key file (PEM, no PEM headers). Must live outside the repo."
}
