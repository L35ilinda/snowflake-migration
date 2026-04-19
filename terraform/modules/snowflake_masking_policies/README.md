# snowflake_masking_policies

Creates Snowflake dynamic masking policies. Applying policies to columns
is done separately (via `ALTER TABLE ... ALTER COLUMN ... SET MASKING POLICY`
or via dbt post-hook).

## Usage

```hcl
module "masking_policies" {
  source = "../../modules/snowflake_masking_policies"

  database_name = "ANALYTICS_DEV"
  schema_name   = "CORE"
  environment   = "dev"

  policies = {
    MP_MASK_STRING_PII = {
      signature   = "val VARCHAR"
      return_type = "VARCHAR"
      body        = <<-SQL
        case
          when current_role() in ('FR_ENGINEER', 'ACCOUNTADMIN') then val
          else '***MASKED***'
        end
      SQL
      comment = "Redact string PII for non-privileged roles."
    }
  }
}
```

## Applying policies

dbt post-hook or manual DDL:

```sql
alter table CORE.DIM_CLIENT
  alter column CLIENT_FIRST_NAME
    set masking policy CORE.MP_MASK_STRING_PII;
```

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `database_name` | `string` | Database to host policies |
| `schema_name` | `string` | Schema to host policies |
| `policies` | `map(object)` | Policy definitions (signature, body, return_type) |
| `environment` | `string` | Comment suffix |

## Outputs

| Name | Description |
|------|-------------|
| `policy_fully_qualified_names` | Map of key -> DB.SCHEMA.NAME |
