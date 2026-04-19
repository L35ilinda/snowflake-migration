variable "database_name" {
  type        = string
  description = "Database to host the SEMANTIC schema and Streamlit app."
}

variable "semantic_schema_name" {
  type        = string
  description = "Schema name for semantic-model metadata (separate from CORE/MARTS data)."
  default     = "SEMANTIC"
}

variable "stage_name" {
  type        = string
  description = "Internal stage that holds the semantic-model YAML and Streamlit app files."
  default     = "MODELS"
}

variable "streamlit_name" {
  type        = string
  description = "Snowflake name for the Streamlit app resource."
  default     = "FSP_ANALYST"
}

variable "streamlit_title" {
  type        = string
  description = "Display title shown in Snowsight."
  default     = "FSP Analyst (Cortex)"
}

variable "main_file" {
  type        = string
  description = "Filename (on stage) of the Streamlit entry point."
  default     = "streamlit_app.py"
}

variable "query_warehouse" {
  type        = string
  description = "Warehouse the Streamlit app uses to execute Cortex-generated SQL."
  default     = "BI_WH"
}

variable "grant_usage_to" {
  type        = list(string)
  description = "Role names that get USAGE on the Streamlit app + SELECT on the stage. Typically [FR_ANALYST, FR_ENGINEER]."
  default     = []
}

variable "cortex_user_roles" {
  type        = list(string)
  description = "Roles that get the SNOWFLAKE.CORTEX_USER database role for calling Cortex Analyst."
  default     = []
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments."
}
