# snowflake_snowpipe

Creates all-VARCHAR landing tables and Snowpipe definitions for a company's datasets.

## Design

- **Landing tables** have all business columns as `VARCHAR`. dbt handles type casting in staging.
- **Metadata columns** added automatically: `_LOADED_AT`, `_SOURCE_FILE`, `_SOURCE_ROW`.
- **Pipes** use `ON_ERROR = CONTINUE` (never fail the pipe) and `MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE` (handles PascalCase headers like risk_benefits).
- **Auto-ingest** is off by default. Use `ALTER PIPE ... REFRESH` to trigger manually, or enable auto-ingest with Azure Event Grid later.

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
