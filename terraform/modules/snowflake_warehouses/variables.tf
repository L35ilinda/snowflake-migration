variable "warehouses" {
  type = map(object({
    size              = optional(string, "XSMALL")
    auto_suspend      = optional(number, 60)
    auto_resume       = optional(bool, true)
    min_cluster_count = optional(number, 1)
    max_cluster_count = optional(number, 1)
    comment           = optional(string, "")
    grant_usage_to    = optional(list(string), [])
  }))
  description = "Map of warehouse name -> config. grant_usage_to lists role names that get USAGE."
}

variable "resource_monitors" {
  type = map(object({
    credit_quota          = number
    notify_triggers       = optional(list(number), [75, 90, 100])
    suspend_trigger       = optional(number, null)
    suspend_immediate_trigger = optional(number, null)
    frequency             = optional(string, "MONTHLY")
    start_timestamp       = optional(string, null)
    warehouses            = optional(list(string), [])
  }))
  description = "Map of resource monitor name -> config. warehouses lists which warehouses to attach."
  default     = {}
}

variable "environment" {
  type        = string
  description = "Environment name, used in comments only."
}
