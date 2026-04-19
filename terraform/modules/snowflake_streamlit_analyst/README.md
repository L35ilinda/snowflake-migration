# snowflake_streamlit_analyst

Provisions a Snowflake-native Streamlit app that answers natural-language questions via Cortex Analyst, plus the supporting schema/stage/grants.

## What this creates

- `<DATABASE>.SEMANTIC` schema — holds analytics metadata (separate from CORE/MARTS data)
- `<DATABASE>.SEMANTIC.MODELS` internal stage — holds semantic model YAML + Streamlit source files
- `<DATABASE>.SEMANTIC.FSP_ANALYST` Streamlit app pointing at the stage
- Grants:
  - `SNOWFLAKE.CORTEX_USER` database role granted to each role in `cortex_user_roles`
  - USAGE on schema, READ on stage, USAGE on Streamlit granted to each role in `grant_usage_to`

## What this does NOT create

- **Stage file contents.** Terraform creates the empty stage. Upload the actual YAML and Streamlit code via `scripts/upload_streamlit_app.py` after `terraform apply`. Snowflake validates at Streamlit *run* time, not create time.

## Usage

```hcl
module "streamlit_analyst" {
  source = "../../modules/snowflake_streamlit_analyst"

  database_name = module.database_layers.database_name
  environment   = var.environment

  grant_usage_to = [
    module.rbac.functional_role_names["FR_ENGINEER"],
    module.rbac.functional_role_names["FR_ANALYST"],
  ]
  cortex_user_roles = [
    module.rbac.functional_role_names["FR_ENGINEER"],
    module.rbac.functional_role_names["FR_ANALYST"],
  ]

  depends_on = [module.database_layers, module.warehouses]
}
```

## Bootstrap sequence

1. `terraform apply` — creates schema, stage, Streamlit resource (app won't run yet because stage is empty).
2. `python scripts/upload_streamlit_app.py` — PUTs `streamlit/app/*` and `streamlit/semantic_model/fsp_marts.yaml` to the stage.
3. Open Snowsight → Streamlit → `FSP_ANALYST` → Run.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `database_name` | `string` | — | Database to host schema and app |
| `semantic_schema_name` | `string` | `SEMANTIC` | Metadata schema |
| `stage_name` | `string` | `MODELS` | Internal stage |
| `streamlit_name` | `string` | `FSP_ANALYST` | App name in Snowsight |
| `streamlit_title` | `string` | `FSP Analyst (Cortex)` | Display title |
| `main_file` | `string` | `streamlit_app.py` | Entry point filename on stage |
| `query_warehouse` | `string` | `BI_WH` | Warehouse for Cortex-generated SQL |
| `grant_usage_to` | `list(string)` | `[]` | Roles that get USAGE on schema/stage/app |
| `cortex_user_roles` | `list(string)` | `[]` | Roles that get `SNOWFLAKE.CORTEX_USER` |
| `environment` | `string` | — | Used in comments |

## Outputs

| Name | Description |
|---|---|
| `semantic_schema_name` | FQN of SEMANTIC schema |
| `stage_fully_qualified_name` | FQN of stage (for PUT) |
| `stage_url` | `@DB.SCHEMA.STAGE` form for Cortex references |
| `streamlit_name` | Snowflake name of the app |
| `streamlit_fully_qualified_name` | FQN of the app |
