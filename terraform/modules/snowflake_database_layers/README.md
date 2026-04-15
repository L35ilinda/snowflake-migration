# Module: `snowflake_database_layers`

Creates a Snowflake database and the layered schema convention from [CLAUDE.md §5](../../../CLAUDE.md):

```text
<database>
|-- RAW_<COMPANY>    (one per entry in raw_companies, append-only landing)
|-- STAGING          (typed, cleaned, conformed)
|-- CORE             (Star Schema + Data Vault domain)
`-- MARTS            (domain-specific, BI-ready)
```

## Inputs

| name | type | description |
|---|---|---|
| `database_name` | string | UPPERCASE database name. Validation enforces uppercase. |
| `environment` | string | Used in object comments only. |
| `raw_companies` | map(string) | Map of `company_id -> COMPANY_NAME` suffix. Example: `{ "01" = "MAIN_BOOK", "02" = "INDIGO_INSURANCE" }`. |

## Outputs

| name | description |
|---|---|
| `database_name` | Created database name. |
| `raw_schema_names` | Map of `company_id → RAW schema name` for implicit dependency on downstream modules. |
| `staging_schema_name` | `STAGING` schema name. |
| `core_schema_name` | `CORE` schema name. |
| `marts_schema_name` | `MARTS` schema name. |

## Notes

- Adding a new company is one line: add a new `company_id -> COMPANY_NAME` entry to `raw_companies` and re-apply.
- Removing a company mapping will destroy the corresponding RAW schema on the next apply. Do not drop a schema that holds real data without a backup or export first.
- This module does not create grants. RBAC is handled by a separate `snowflake_rbac` module.
