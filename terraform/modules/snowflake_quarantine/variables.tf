variable "database_name" {
  type        = string
  description = "Database containing the quarantine schema."
}

variable "schema_name" {
  type        = string
  description = "Schema where pipe_errors table and capture task live (created externally)."
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse the capture task runs on."
}

variable "pipe_fully_qualified_names" {
  type        = list(string)
  description = "Fully qualified pipe names (DB.SCHEMA.PIPE) to monitor for rejected rows via VALIDATE_PIPE_LOAD."
  validation {
    condition     = length(var.pipe_fully_qualified_names) > 0
    error_message = "At least one pipe must be supplied."
  }
}

variable "schedule_minutes" {
  type        = number
  description = "How often (minutes) the capture task runs."
  default     = 5
}

variable "lookback_minutes" {
  type        = number
  description = "How far back (minutes) the task scans pipe load history each run. Should be 2x schedule_minutes to absorb skew."
  default     = 10
}

variable "table_name" {
  type        = string
  description = "Name of the quarantine table."
  default     = "PIPE_ERRORS"
}

variable "task_name" {
  type        = string
  description = "Name of the capture task."
  default     = "TSK_CAPTURE_PIPE_ERRORS"
}

variable "environment" {
  type        = string
  description = "Environment name (used in comments)."
}
