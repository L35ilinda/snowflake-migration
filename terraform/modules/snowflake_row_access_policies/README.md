# snowflake_row_access_policies

Defines Snowflake row access policies for use by attaching modules
(typically dbt post-hooks). Mirrors the shape of `snowflake_masking_policies`
so the two read consistently in `environments/dev/main.tf`.

## Why this exists

Multi-tenant CORE/MARTS tables share rows from every tenant. Without row
access policies, any role with `SELECT` sees every tenant. RAP is the
Snowflake-native primitive for hiding rows based on `current_role()` and
the row's own values. See ADR-0020.

This module owns **policy definition** only. **Attachment** is a separate
concern — handled in dbt for tables built by dbt (post-hook), or via
direct `ALTER TABLE ... ADD ROW ACCESS POLICY` for non-dbt-managed objects.

## Design

`snowflake_row_access_policy` is a first-class provider resource. Each
policy declares an argument list and a SQL body returning `BOOLEAN`
(true = row visible).

For tenant isolation specifically, the body is a `case` keyed off
`current_role()`:

```sql
case
  when current_role() in ('ACCOUNTADMIN', 'FR_ENGINEER', 'FR_CI', 'FR_ANALYST') then true
  when current_role() = 'FR_ANALYST_MAIN_BOOK' and company = 'MAIN_BOOK' then true
  ...
  else false
end
```

The argument name (`company` here) must match the column name on the
attached table. Snowflake passes that column's value into the policy
function on every row evaluation.

## APPLY grant — important

Like masking policies, attaching a RAP requires `APPLY` on the policy
object. In this project we grant `APPLY` to `FR_ENGINEER` so dbt's
post-hook can attach during `dbt build` against `ANALYTICS_DEV`. The
grant lives in `environments/dev/main.tf` alongside the masking-policy
APPLY grant.

## Usage

```hcl
module "row_access_policies" {
  source = "../../modules/snowflake_row_access_policies"

  database_name = "ANALYTICS_DEV"
  schema_name   = "CORE"
  environment   = "dev"

  policies = {
    RAP_TENANT_ISOLATION = {
      signature = "company VARCHAR"
      body      = <<-SQL
        case
          when current_role() in ('ACCOUNTADMIN', 'FR_ENGINEER', 'FR_CI', 'FR_ANALYST') then true
          when current_role() = 'FR_ANALYST_MAIN_BOOK'         and company = 'MAIN_BOOK'         then true
          when current_role() = 'FR_ANALYST_INDIGO_INSURANCE'  and company = 'INDIGO_INSURANCE'  then true
          when current_role() = 'FR_ANALYST_HORIZON_ASSURANCE' and company = 'HORIZON_ASSURANCE' then true
          else false
        end
      SQL
      comment   = "Multi-tenant row isolation by company. See ADR-0020."
    }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `database_name` | `string` | — | Database where policies live |
| `schema_name`   | `string` | — | Schema where policies live (typically CORE) |
| `policies`      | `map(object)` | — | Map of policy name -> { signature, body, comment } |
| `environment`   | `string` | — | Environment label |

`signature` example: `"company VARCHAR"` (single argument). Multi-arg
policies are possible at the Snowflake level but the current module
splits on a single space — extend if you need multi-arg.

## Outputs

| Name | Description |
|------|-------------|
| `policy_fully_qualified_names` | Map of policy key -> `DB.SCHEMA.NAME` |

## Operations

```sql
-- Inspect policy attachments
select *
from snowflake.account_usage.policy_references
where policy_name = 'RAP_TENANT_ISOLATION'
order by ref_database_name, ref_schema_name, ref_entity_name;

-- Detach manually (e.g. before dropping a table)
alter table analytics_dev.core.dim_client drop all row access policies;
```