# snowflake_warehouses

Manages workload-separated warehouses and resource monitors.

## Usage

```hcl
module "warehouses" {
  source = "../../modules/snowflake_warehouses"

  environment = "dev"

  warehouses = {
    LOAD_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      grant_usage_to = ["FR_ENGINEER"]
      comment        = "Snowpipe and COPY INTO workloads."
    }
    TRANSFORM_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      grant_usage_to = ["FR_ENGINEER"]
      comment        = "dbt transformations."
    }
    BI_WH = {
      size           = "XSMALL"
      auto_suspend   = 60
      grant_usage_to = ["FR_ENGINEER", "FR_ANALYST"]
      comment        = "BI and ad-hoc queries."
    }
  }

  resource_monitors = {
    RM_DEV_ACCOUNT = {
      credit_quota          = 10
      frequency             = "MONTHLY"
      notify_triggers       = [75, 90, 100]
      suspend_trigger       = 100
      suspend_immediate_trigger = 110
    }
  }
}
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `warehouses` | `map(object)` | Warehouse definitions (size, auto_suspend, grant_usage_to, etc.) |
| `resource_monitors` | `map(object)` | Resource monitor definitions (credit_quota, triggers, frequency) |
| `environment` | `string` | Environment name for comments |

## Outputs

| Name | Description |
|------|-------------|
| `warehouse_names` | Map of key -> warehouse name |
| `resource_monitor_names` | Map of key -> monitor name |

## Notes

- All warehouses start suspended (`initially_suspended = true`) to avoid burning credits.
- Auto-suspend defaults to 60s per CLAUDE.md §5.
- `grant_usage_to` accepts role names — wire these to RBAC functional roles.
