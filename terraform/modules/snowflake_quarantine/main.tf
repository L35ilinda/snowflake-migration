terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# pipe_errors — shared quarantine table across all monitored pipes.
# Mirrors the columns returned by TABLE(VALIDATE_PIPE_LOAD(...)) plus
# pipe_name (the source pipe FQN) and captured_at (when the task wrote it).
# ---------------------------------------------------------------------------

resource "snowflake_table" "pipe_errors" {
  database = var.database_name
  schema   = var.schema_name
  name     = var.table_name

  column {
    name     = "PIPE_NAME"
    type     = "VARCHAR"
    nullable = false
  }

  # error / file are the most useful free-text columns for triage.
  column {
    name = "ERROR"
    type = "VARCHAR"
  }
  column {
    name = "FILE_NAME"
    type = "VARCHAR"
  }

  column {
    name = "LINE"
    type = "NUMBER(38,0)"
  }
  column {
    name = "CHARACTER_POS"
    type = "NUMBER(38,0)"
  }
  column {
    name = "BYTE_OFFSET"
    type = "NUMBER(38,0)"
  }

  column {
    name = "CATEGORY"
    type = "VARCHAR"
  }
  column {
    name = "CODE"
    type = "VARCHAR"
  }
  column {
    name = "SQL_STATE"
    type = "VARCHAR"
  }
  column {
    name = "COLUMN_NAME"
    type = "VARCHAR"
  }
  column {
    name = "ROW_NUMBER"
    type = "NUMBER(38,0)"
  }
  column {
    name = "ROW_START_LINE"
    type = "NUMBER(38,0)"
  }

  # Full text of the rejected source row — VARIANT would be tempting but
  # the rejected row may not be parseable JSON, so VARCHAR is safer.
  column {
    name = "REJECTED_RECORD"
    type = "VARCHAR"
  }

  column {
    name = "CAPTURED_AT"
    type = "TIMESTAMP_NTZ(9)"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }

  comment = "Snowpipe rejected-row capture (${var.environment}). Populated by ${var.task_name} via VALIDATE_PIPE_LOAD. See ADR-0012."
}

# ---------------------------------------------------------------------------
# Capture task — every N minutes, MERGE in new errors from each pipe's
# VALIDATE_PIPE_LOAD output. MERGE on (pipe_name, file_name, row_number, line)
# dedupes across overlapping lookback windows.
# ---------------------------------------------------------------------------

locals {
  table_fqn = "\"${var.database_name}\".\"${var.schema_name}\".\"${var.table_name}\""

  # One SELECT per pipe, UNIONed. CHARACTER is a Snowflake reserved word,
  # so it's quoted on the read side and aliased to character_pos.
  per_pipe_select = join("\n  UNION ALL\n  ", [
    for pipe_fqn in var.pipe_fully_qualified_names :
    join(" ", [
      "SELECT '${pipe_fqn}' AS pipe_name,",
      "error, file AS file_name, line, \"CHARACTER\" AS character_pos,",
      "byte_offset, category, code, sql_state, column_name,",
      "row_number, row_start_line, rejected_record",
      "FROM TABLE(VALIDATE_PIPE_LOAD(",
      "PIPE_NAME => '${pipe_fqn}',",
      "START_TIME => DATEADD('minute', -${var.lookback_minutes}, CURRENT_TIMESTAMP())",
      "))",
    ])
  ])

  capture_sql = <<-SQL
    MERGE INTO ${local.table_fqn} t
    USING (
      ${local.per_pipe_select}
    ) s
    ON t.pipe_name = s.pipe_name
       AND COALESCE(t.file_name, '') = COALESCE(s.file_name, '')
       AND COALESCE(t.row_number, -1) = COALESCE(s.row_number, -1)
       AND COALESCE(t.line, -1) = COALESCE(s.line, -1)
    WHEN NOT MATCHED THEN INSERT (
      pipe_name, error, file_name, line, character_pos, byte_offset,
      category, code, sql_state, column_name, row_number, row_start_line,
      rejected_record, captured_at
    ) VALUES (
      s.pipe_name, s.error, s.file_name, s.line, s.character_pos, s.byte_offset,
      s.category, s.code, s.sql_state, s.column_name, s.row_number, s.row_start_line,
      s.rejected_record, CURRENT_TIMESTAMP()
    )
  SQL
}

resource "snowflake_task" "capture_pipe_errors" {
  database  = var.database_name
  schema    = var.schema_name
  name      = var.task_name
  warehouse = var.warehouse_name

  schedule {
    minutes = var.schedule_minutes
  }

  sql_statement = local.capture_sql
  started       = true

  comment = "Captures Snowpipe rejected rows into ${var.table_name} via VALIDATE_PIPE_LOAD. ADR-0012. (${var.environment})"

  # Task references the destination table in its body — table must exist first.
  depends_on = [snowflake_table.pipe_errors]
}
