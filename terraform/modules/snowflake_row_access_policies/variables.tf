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
    signature = string
    body      = string
    comment   = optional(string, "")
  }))
  description = <<-DOC
    Map of policy name -> definition. signature is the column argument list
    (e.g. "company VARCHAR"); body is the SQL case expression returning a
    BOOLEAN (true = row visible). RAP return type is fixed to BOOLEAN by
    Snowflake — no return_type input.
  DOC
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments."
}