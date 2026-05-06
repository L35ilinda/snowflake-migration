# snowflake_quarantine_alert

Fires a Snowflake-native email alert when new rows land in the Snowpipe
quarantine table. Closes the ADR-0012 known-limitation
"no alerting on pipe errors."

## Why this exists

`snowflake_quarantine` captures rejected rows via a scheduled task, but there
was no signal when new errors appeared. Operators had to poll the table
manually. This module adds a Snowflake-side alert that polls the table on the
same cadence as the capture task and emails operators when the delta is
non-empty.

Everything is Snowflake-native — no external monitoring stack, no Azure
Monitor action group. The cost profile matches the capture task itself.

## Design

- **`snowflake_email_notification_integration`** (`NI_EMAIL_OPS`) — the
  Snowflake-native email channel. `allowed_recipients` restricts who the
  integration can email.
- **`snowflake_alert`** (`ALR_QUARANTINE_NEW_ERRORS`) — evaluates the
  condition every `schedule_minutes`. Condition is a `SELECT 1 … LIMIT 1`
  on the quarantine table filtered to `captured_at` within
  `lookback_minutes`. If any row is returned, the action fires.
- **Action** calls `SYSTEM$SEND_EMAIL` with a short subject + triage-query
  body. The email's job is "go look" — operators query the quarantine table
  for detail. Keeps the alert SQL simple and the email format stable.

### Recipient verification — important

`SYSTEM$SEND_EMAIL` only delivers to addresses that match the `EMAIL`
property set on a Snowflake user in the same account. Listing an address
in `allowed_recipients` is necessary but not sufficient.

For this project the only operator is `LSILINDA`; the email is set on that
user via a `snowflake_execute` one-shot in `environments/dev/main.tf` (see
the `lsilinda_email` resource). When adding additional recipients, set the
corresponding user's email first, then add to `recipient_emails` here.

## Usage

```hcl
module "quarantine_alert" {
  source = "../../modules/snowflake_quarantine_alert"

  database_name                         = "ANALYTICS_DEV"
  schema_name                           = "RAW_QUARANTINE"
  warehouse_name                        = "LOAD_WH"
  quarantine_table_fully_qualified_name = module.quarantine.table_fully_qualified_name
  email_integration_name                = "NI_EMAIL_OPS"
  recipient_emails                      = ["eric.silinda@gmail.com"]
  environment                           = "dev"
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `database_name` | `string` | — | Database containing the alert |
| `schema_name` | `string` | — | Schema for the alert (typically the quarantine schema) |
| `warehouse_name` | `string` | — | Warehouse the alert runs on |
| `quarantine_table_fully_qualified_name` | `string` | — | DB.SCHEMA.TABLE of the quarantine table |
| `email_integration_name` | `string` | — | UPPERCASE name for the email integration |
| `alert_name` | `string` | `ALR_QUARANTINE_NEW_ERRORS` | Alert name |
| `recipient_emails` | `list(string)` | — | Addresses to notify (must match EMAIL on a Snowflake user) |
| `schedule_minutes` | `number` | `5` | Alert evaluation cadence |
| `lookback_minutes` | `number` | `5` | Scan window per evaluation |
| `environment` | `string` | — | Environment label |

## Outputs

| Name | Description |
|------|-------------|
| `email_integration_name` | Email integration name |
| `alert_name` | Alert name |
| `alert_fully_qualified_name` | DB.SCHEMA.ALERT |

## Operations

```sql
-- See alert state and last run
show alerts in schema analytics_dev.raw_quarantine;

-- Pause / resume the alert
alter alert analytics_dev.raw_quarantine.alr_quarantine_new_errors suspend;
alter alert analytics_dev.raw_quarantine.alr_quarantine_new_errors resume;

-- Manual trigger for testing (inserts a synthetic row then waits up to 5 min)
insert into analytics_dev.raw_quarantine.pipe_errors (pipe_name, error, file_name, captured_at)
values ('SYNTHETIC_TEST', 'manual alert test', 'test.csv', current_timestamp());
```

## Cost

XS warehouse, <1s per evaluation every 5 min, auto-suspend 60s. Shares
`LOAD_WH` with the capture task. Net cost delta: negligible — alerts
without matches don't start the warehouse at all (condition SQL runs on
serverless compute).