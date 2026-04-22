# snowflake_quarantine

Captures Snowpipe rejected rows into a single shared table via a scheduled
Snowflake Task that polls `VALIDATE_PIPE_LOAD()` for every monitored pipe.

## Why this exists

Snowpipes in this project run with `ON_ERROR = CONTINUE`. That keeps the pipe
healthy when source data is malformed, but the rejected rows are silently
dropped. `VALIDATE_PIPE_LOAD()` is the documented Snowflake-native API for
recovering them — this module wraps it in a recurring task so triage data
accumulates without manual polling. See ADR-0012.

## Design

- **One shared table** (`PIPE_ERRORS`) across all pipes — `pipe_name` filters
  to one source. Avoids an 18-way UNION when querying "today's failures".
- **One task** UNION-ALLs `VALIDATE_PIPE_LOAD()` over every supplied pipe FQN
  every `schedule_minutes` (default 5).
- **MERGE on (pipe_name, file_name, row_number, line)** dedupes across the
  overlapping `lookback_minutes` window (default 10 min, i.e. 2x the schedule
  to absorb skew).
- **Owner-mode task** running as the role that applied Terraform
  (typically ACCOUNTADMIN). The owner needs `MONITOR` on every pipe and
  `INSERT` on the quarantine table — both implicit for ACCOUNTADMIN.

## Usage

```hcl
module "quarantine" {
  source = "../../modules/snowflake_quarantine"

  database_name  = "ANALYTICS_DEV"
  schema_name    = "RAW_QUARANTINE"   # caller creates the schema
  warehouse_name = "LOAD_WH"
  environment    = "dev"

  pipe_fully_qualified_names = [
    "ANALYTICS_DEV.RAW_MAIN_BOOK.PIPE_MAIN_BOOK_VALUATIONS",
    # ... 17 more
  ]
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `database_name` | `string` | — | Database containing the quarantine schema |
| `schema_name` | `string` | — | Schema for the table + task (created externally) |
| `warehouse_name` | `string` | — | Warehouse the task runs on |
| `pipe_fully_qualified_names` | `list(string)` | — | Pipes to monitor |
| `schedule_minutes` | `number` | `5` | Task cadence |
| `lookback_minutes` | `number` | `10` | History window per run; should be ≥ 2× schedule |
| `table_name` | `string` | `PIPE_ERRORS` | Quarantine table name |
| `task_name` | `string` | `TSK_CAPTURE_PIPE_ERRORS` | Capture task name |
| `environment` | `string` | — | Environment label |

## Outputs

| Name | Description |
|------|-------------|
| `table_name` | Quarantine table name |
| `table_fully_qualified_name` | DB.SCHEMA.TABLE |
| `task_name` | Capture task name |

## Operations

```sql
-- See most recent failures across all pipes
select pipe_name, file_name, error, captured_at
from analytics_dev.raw_quarantine.pipe_errors
order by captured_at desc
limit 100;

-- Per-pipe error counts last 24h
select pipe_name, count(*) as errors
from analytics_dev.raw_quarantine.pipe_errors
where captured_at > dateadd('hour', -24, current_timestamp())
group by 1
order by 2 desc;

-- Pause / resume the task
alter task analytics_dev.raw_quarantine.tsk_capture_pipe_errors suspend;
alter task analytics_dev.raw_quarantine.tsk_capture_pipe_errors resume;
```

## Cost

XS warehouse, ~1-2s execution every 5 min, auto-suspend 60s.
Net ≈ 0.05-0.10 credit/month on `LOAD_WH`. Negligible.
