# snowflake_snowpipe

Creates all-VARCHAR landing tables and Snowpipe definitions for a company's datasets.

## Design

- **Landing tables** have all business columns as `VARCHAR`. dbt handles type casting in staging.
- **Metadata column** added automatically: `_LOADED_AT TIMESTAMP_NTZ`. Populated by the pipe via `CURRENT_TIMESTAMP()` in a transformed COPY (column DEFAULTs do not fire on `COPY INTO`).
- **Pipes** use `ON_ERROR = CONTINUE` (never fail the pipe) and a positional transformed COPY (`SELECT $1, $2, ..., $N, CURRENT_TIMESTAMP()`). `MATCH_BY_COLUMN_NAME` is not used because it conflicts with `SKIP_HEADER` on the file format — column order in the `datasets` map must match CSV column order.
- **Auto-ingest** is enabled when `notification_integration_name` is set (passed from `snowpipe_azure_notifications`). Without it, pipes stay manual-refresh only.
- **Rejected rows** are silently dropped by `ON_ERROR = CONTINUE`; the `snowflake_quarantine` module captures them via `VALIDATE_PIPE_LOAD()`. See ADR-0012.

## Usage

```hcl
module "main_book_pipes" {
  source = "../../modules/snowflake_snowpipe"

  database_name    = "ANALYTICS_DEV"
  raw_schema_name  = "RAW_MAIN_BOOK"
  stage_name       = "STG_MAIN_BOOK"
  file_format_name = "FF_CSV_MAIN_BOOK"
  environment      = "dev"

  datasets = {
    main_book_valuations = {
      columns      = ["advisor_identifier", "client_title", ...]
      file_pattern = ".*main_book_valuations.*[.]csv"
    }
  }
}
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `database_name` | `string` | Database name |
| `raw_schema_name` | `string` | RAW schema name |
| `stage_name` | `string` | External stage (from company_ingest module) |
| `file_format_name` | `string` | CSV file format (from company_ingest module) |
| `datasets` | `map(object)` | Dataset definitions: columns + file_pattern |
| `environment` | `string` | Environment name for comments |

## Outputs

| Name | Description |
|------|-------------|
| `table_names` | Map of dataset key -> landing table name |
| `pipe_names` | Map of dataset key -> pipe name |
