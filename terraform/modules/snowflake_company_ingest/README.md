# Module: `snowflake_company_ingest`

Creates the per-company ingest surface: one CSV file format and one external stage, both inside the company's named RAW schema. Call it once per company; each call is independent.

```text
ANALYTICS_DEV.RAW_MAIN_BOOK
|-- FF_CSV_COMPANY_NN         (file format - per-company so encodings and delimiters can diverge later)
`-- STG_COMPANY_NN_OUTBOUND   (external stage pointing at the company's Azure container)
```

## Inputs

| name | type | description |
|---|---|---|
| `company_id` | string | Two-digit zero-padded identifier, for example `"01"`. Validated by regex. |
| `database_name` | string | Database holding the RAW schema. |
| `raw_schema_name` | string | Named RAW schema such as `RAW_MAIN_BOOK`. Pass from `module.snowflake_database_layers.raw_schema_names[<id>]` for implicit dependency. |
| `storage_integration_name` | string | Storage integration from `snowflake_storage_integration`. |
| `storage_account_name` | string | Azure storage account name. |
| `container_name` | string | Azure blob container name for this company's outbound files. |
| `environment` | string | Used in comments only. |

## Outputs

| name | description |
|---|---|
| `file_format_name` | `FF_CSV_COMPANY_NN` - for reference in pipes. |
| `stage_name` | `STG_COMPANY_NN_OUTBOUND`. |
| `stage_fully_qualified_name` | `<database>.<schema>.<stage>` for `LIST` / `COPY INTO`. |

## File format choices

The format is deliberately forgiving on ingest:

- `error_on_column_count_mismatch = false` - bad rows become nulls or quarantined rows later; the whole file does not fail here.
- `replace_invalid_characters = true` - bad bytes become replacement characters instead of failing the load surface.
- `null_if` includes `""`, `"NULL"`, `"null"`, and `"\\N"` - common null sentinels from different suppliers.
- `trim_space = true` - whitespace-padded fields are common in SFTP dumps.

Strict validation lives at the pipe/copy layer and in dbt staging models, not here. Failing at the file-format level means one bad row can kill an entire Snowpipe file.

## Verify after apply

```sql
USE ROLE ACCOUNTADMIN;   -- until dedicated roles exist
LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND/Outbound;
```

A successful `LIST` proves the storage integration is healthy, Azure consent is complete, Blob Data Reader has been granted, the stage URL is correct, and the file format is usable.
