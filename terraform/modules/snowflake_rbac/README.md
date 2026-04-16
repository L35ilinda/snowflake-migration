# snowflake_rbac

Manages Snowflake RBAC following the access-role / functional-role pattern.

## Hierarchy

```
User → Functional Role (FR_*) → Access Role (AR_*) → Object Privileges
```

- **Access roles** get object-level grants (USAGE, SELECT, CREATE, ALL) on a specific schema.
- **Functional roles** aggregate access roles for a job function.
- **Users** are granted functional roles only — never access roles or object privileges directly.

## Usage

```hcl
module "rbac" {
  source = "../../modules/snowflake_rbac"

  database_name = "ANALYTICS_DEV"
  environment   = "dev"

  schemas = {
    raw_main_book        = "RAW_MAIN_BOOK"
    raw_indigo_insurance = "RAW_INDIGO_INSURANCE"
    staging              = "STAGING"
    core                 = "CORE"
    marts                = "MARTS"
  }

  functional_roles = {
    FR_ENGINEER = {
      comment            = "Full read-write access for data engineers."
      access_role_grants = ["raw_main_book_rw", "staging_rw", "core_rw", "marts_rw"]
    }
    FR_ANALYST = {
      comment            = "Read-only access for analysts."
      access_role_grants = ["staging_ro", "core_ro", "marts_ro"]
    }
  }

  user_grants = {
    LSILINDA = ["FR_ENGINEER"]
  }
}
```

## What gets created per schema

Each schema entry produces two access roles:

| Role | Grants |
|------|--------|
| `AR_<DB>_<SCHEMA>_RW` | USAGE on DB + schema, CREATE TABLE/VIEW, ALL on future tables/views |
| `AR_<DB>_<SCHEMA>_RO` | USAGE on DB + schema, SELECT on future tables/views |

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `database_name` | `string` | Database to grant access on |
| `schemas` | `map(string)` | Map of schema key -> schema name |
| `functional_roles` | `map(object)` | Functional role definitions with access role grants |
| `user_grants` | `map(list(string))` | Map of username -> functional roles to grant |
| `environment` | `string` | Environment name for comments |

## Outputs

| Name | Description |
|------|-------------|
| `access_role_names` | Map of access role key -> role name |
| `functional_role_names` | Map of functional role key -> role name |
