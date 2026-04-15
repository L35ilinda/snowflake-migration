# Module: `snowflake_company_ingest`

Creates the per-company ingest surface: one CSV file format and one external stage, both inside the company's named RAW schema. Call it once per company; each call is independent.

```
ANALYTICS_DEV.RAW_MAIN_BOOK
├── FF_CSV_COMPANY_NN         (file format — per-company so encodings/delimiters can diverge later)
└── STG_COMPANY_NN_OUTBOUND   (external stage pointing at the company's Azure container)
```

## Inputs

| name | type | description |
|---|---|---|
| `company_id` | string | Two-digit zero-padded identifier, e.g. `"01"`. Validated by regex. |
| `database_name` | string | Database holding the RAW schema. |
| `raw_schema_name` | string | Named RAW schema such as `RAW_MAIN_BOOK`. Pass from `module.snowflake_database_layers.raw_schema_names[<id>]` for implicit dependency. |
| `storage_integration_name` | string | Storage integration from `snowflake_storage_integration` module. |
| `storage_account_name` | string | Azure storage account name. |
| `container_name` | string | Azure blob container name for this company's outbound files. |
| `environment` | string | Used in comments only. |

## Outputs

| name | description |
|---|---|
| `file_format_name` | `FF_CSV_COMPANY_NN` — for reference in pipes. |
| `stage_name` | `STG_COMPANY_NN_OUTBOUND`. |
| `stage_fully_qualified_name` | `<database>.<schema>.<stage>` for `LIST` / `COPY INTO`. |

## File format choices

The format is deliberately **forgiving** on ingest:

- `error_on_column_count_mismatch = false` — bad rows become nulls/quarantined, the whole file doesn't fail.
- `replace_invalid_characters = true` — bad bytes become `?` instead of failing.
- `null_if` includes `""`, `"NULL"`, `"null"`, and `"\\N"` — three common null sentinels from different suppliers.
- `trim_space = true` — whitespace-padded fields are common in SFTP dumps.

Strict validation lives at the pipe/copy layer (future `snowflake_pipe` module) and in dbt staging models, not here. Failing at the file-format level means one bad row kills an entire Snowpipe file.

## Verify after apply

```sql
USE ROLE ACCOUNTADMIN;   -- until dedicated roles exist
LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND;
-- Expect ~70 files listed from fsp-company-01/Outbound/ (actual count depends on file-split decision).
```

A successful `LIST` proves: storage integration healthy + Entra consent done + Blob Data Reader granted + stage URL correct + file format valid.
