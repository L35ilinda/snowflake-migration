# ADR-0006: Named RAW schemas over numeric tenant suffixes

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

The project started with placeholder-style raw schema names such as `RAW_COMPANY_01`, `RAW_COMPANY_02`, and `RAW_COMPANY_03`. That works mechanically, but it reads like scaffolding rather than an intentional enterprise platform. The portfolio story is stronger if the Snowflake layer reflects the tenant names that appear in the source-data dictionary and business narrative.

At the time of this decision, Azure container names were provisioned as `fsp-company-01/02/03`. These were later renamed to descriptive names (`fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`) and the numeric identifiers are now only used as Terraform map keys.

## Options considered

1. **Keep numeric RAW schemas** - straightforward and explicit about the multi-tenant pattern. Downside: looks generic and tutorial-like in SQL, architecture diagrams, and screenshots.
2. **Use named RAW schemas and rename everything else to match** - strongest readability in Snowflake, but forces Azure, container, and stage naming churn that adds work with little architectural benefit.
3. **Use named RAW schemas while keeping container and stage IDs numeric** - Snowflake reads like a real tenant model, while Terraform keeps a stable `company_id -> container -> schema` mapping.

## Decision

Chose **named RAW schemas while keeping the physical ingest identifiers numeric**.

The initial three tenants are:

- `01 -> RAW_MAIN_BOOK`
- `02 -> RAW_INDIGO_INSURANCE`
- `03 -> RAW_HORIZON_ASSURANCE`

This keeps the Azure and storage side simple and already provisioned, while making the Snowflake database layer much more legible in demos, screenshots, and SQL reviews.

## Consequences

- Terraform's database-layer module now accepts a `company_id -> COMPANY_NAME` mapping instead of a bare list of numeric IDs.
- Downstream ingest modules now use `company_name` for descriptive Snowflake object names (`STG_MAIN_BOOK`, `FF_CSV_MAIN_BOOK`). The `company_id` key is retained in Terraform for map iteration only.
- Documentation must spell out the mapping explicitly so readers do not lose the multi-tenant pattern when they stop seeing `RAW_COMPANY_NN`.
- Adding a new tenant now requires picking both a numeric ingest ID and a Snowflake-safe uppercase schema suffix.
