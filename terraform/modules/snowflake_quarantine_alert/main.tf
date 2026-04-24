terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Email notification integration — Snowflake-native email channel.
# Recipients must also exist as the EMAIL property on a Snowflake user in
# this account (Snowflake only sends to verified addresses). Setting that
# on LSILINDA is handled in environments/dev (snowflake_execute one-shot).
# ---------------------------------------------------------------------------

resource "snowflake_email_notification_integration" "this" {
  name               = var.email_integration_name
  enabled            = true
  allowed_recipients = var.recipient_emails
  comment            = "Ops email channel for Snowflake alerts (${var.environment}). See ADR-0012 follow-up."
}

# ---------------------------------------------------------------------------
# Alert: fires when new rows have landed in the quarantine table within the
# last `lookback_minutes` window.
#
# Condition returns rows iff the delta is non-empty -> action fires.
# Action body is intentionally terse: the job of the email is "go look",
# not "deliver the payload". Operators query the table directly for detail.
# ---------------------------------------------------------------------------

locals {
  condition_sql = <<-SQL
    SELECT 1
    FROM ${var.quarantine_table_fully_qualified_name}
    WHERE captured_at > DATEADD('minute', -${var.lookback_minutes}, CURRENT_TIMESTAMP())
    LIMIT 1
  SQL

  # The body is embedded as a single-quoted SQL literal inside CALL
  # SYSTEM$SEND_EMAIL(..., 'body'). Keep it free of single quotes and SQL
  # punctuation — they would need to be doubled to escape, and the payload
  # isn't worth the quoting ceremony. The email's job is "go look"; the
  # triage query lives in the module README and in RAW_QUARANTINE docs.
  email_subject = "Snowpipe quarantine: new rejected rows detected (${var.environment})"

  email_body = "New rejected rows have landed in ${var.quarantine_table_fully_qualified_name} within the last ${var.lookback_minutes} minutes. Query the quarantine table for pipe_name, file_name, error, and captured_at."

  action_sql = "CALL SYSTEM$SEND_EMAIL('${snowflake_email_notification_integration.this.name}', '${join(",", var.recipient_emails)}', '${local.email_subject}', '${local.email_body}')"
}

resource "snowflake_alert" "this" {
  database  = var.database_name
  schema    = var.schema_name
  name      = var.alert_name
  warehouse = var.warehouse_name

  alert_schedule {
    interval = var.schedule_minutes
  }

  condition = local.condition_sql
  action    = local.action_sql
  enabled   = true

  comment = "Fires SYSTEM$SEND_EMAIL when new rows appear in ${var.quarantine_table_fully_qualified_name} (${var.environment}). ADR-0012 follow-up."
}