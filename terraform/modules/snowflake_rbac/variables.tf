variable "database_name" {
  type        = string
  description = "Database to grant access on (e.g. ANALYTICS_DEV)."
}

variable "schemas" {
  type        = map(string)
  description = "Map of schema key -> schema name. Each gets an RW + RO access role. Example: { staging = \"STAGING\", core = \"CORE\" }."
}

variable "functional_roles" {
  type = map(object({
    access_role_grants = list(string)
    comment            = optional(string, "")
  }))
  description = "Map of functional role name -> config. access_role_grants lists the access role keys (e.g. [\"staging_rw\", \"core_rw\"]) to grant to this functional role."
}

variable "user_grants" {
  type        = map(list(string))
  description = "Map of username -> list of functional role names to grant. Example: { LSILINDA = [\"FR_ENGINEER\"] }."
  default     = {}
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments only."
}
