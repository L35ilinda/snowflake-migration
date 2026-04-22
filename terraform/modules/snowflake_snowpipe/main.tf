terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Landing tables — all columns VARCHAR. dbt handles typing in staging.
# ---------------------------------------------------------------------------

resource "snowflake_table" "landing" {
  for_each = var.datasets

  database = var.database_name
  schema   = var.raw_schema_name
  name     = upper(each.key)

  dynamic "column" {
    for_each = each.value.columns
    content {
      name = upper(column.value)
      type = "VARCHAR"
    }
  }

  # Audit column — records when each row was loaded.
  column {
    name = "_LOADED_AT"
    type = "TIMESTAMP_NTZ"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }

  comment = "Raw landing table for ${each.key} (${var.environment}). All columns VARCHAR; dbt types in staging."
}

# ---------------------------------------------------------------------------
# Snowpipes — one per dataset, COPY INTO from stage with file pattern.
# ---------------------------------------------------------------------------

resource "snowflake_pipe" "this" {
  for_each = var.datasets

  # Pipe references the landing table in its COPY INTO — table must exist first.
  depends_on = [snowflake_table.landing]

  database = var.database_name
  schema   = var.raw_schema_name
  name     = upper("pipe_${each.key}")

  # Transformed COPY: enumerate the source columns positionally ($1..$N) and
  # append CURRENT_TIMESTAMP() so _LOADED_AT is populated on every load.
  # Column DEFAULTs do not fire on COPY INTO — only on explicit INSERT — so
  # the simpler "COPY INTO tbl FROM @stage" form leaves _LOADED_AT NULL.
  copy_statement = <<-SQL
    COPY INTO "${var.database_name}"."${var.raw_schema_name}"."${upper(each.key)}" (
      ${join(", ", [for c in each.value.columns : "\"${upper(c)}\""])},
      "_LOADED_AT"
    )
    FROM (
      SELECT
        ${join(", ", [for i in range(length(each.value.columns)) : format("$%d", i + 1)])},
        CURRENT_TIMESTAMP()
      FROM @"${var.database_name}"."${var.raw_schema_name}"."${var.stage_name}"
    )
    FILE_FORMAT = (FORMAT_NAME = "${var.database_name}"."${var.raw_schema_name}"."${var.file_format_name}")
    PATTERN = '${each.value.file_pattern}'
    ON_ERROR = CONTINUE
  SQL

  # When a notification integration is supplied, AUTO_INGEST fires the pipe
  # on every blob-created event. Otherwise the pipe stays manual-refresh.
  auto_ingest = var.notification_integration_name != null
  integration = var.notification_integration_name

  comment = "Snowpipe for ${each.key} from ${var.stage_name} (${var.environment})."
}
