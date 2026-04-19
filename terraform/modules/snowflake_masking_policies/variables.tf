variable "database_name" {
  type        = string
  description = "Database where policies live."
}

variable "schema_name" {
  type        = string
  description = "Schema where policies live (typically CORE)."
}

variable "policies" {
  type = map(object({
    signature  = string
    body       = string
    return_type = string
    comment    = optional(string, "")
  }))
  description = <<-DOC
    Map of policy name -> definition. signature is the column argument list
    (e.g. "val VARCHAR"), body is the SQL case expression returning the
    masked value, return_type is the SQL type returned.
  DOC
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments."
}
