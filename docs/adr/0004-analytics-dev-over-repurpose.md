# ADR-0004: Fresh ANALYTICS_DEV database over repurposing FSP_DATA_INTEGRATION_DB

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

The Snowflake account already has `FSP_DATA_INTEGRATION_DB` from earlier ad-hoc learning work. It holds one 1000-row `MOCK_DATA` table in `PUBLIC`. The project's target naming convention (CLAUDE.md §5) is `<PURPOSE>_<ENV>` — e.g. `ANALYTICS_DEV`, `ANALYTICS_PROD`.

Two paths: repurpose the existing database (rename or reuse in place) or create a fresh one aligned with the convention and leave the old one as a sandbox.

## Options considered

1. **Repurpose `FSP_DATA_INTEGRATION_DB`.** Avoids creating a second database. Keeps all historic artifacts in one place. But the name doesn't match the convention, which sets a bad precedent on day one. Renaming is possible but touches any existing grants, shares, and tooling references.
2. **Create fresh `ANALYTICS_DEV`.** Clean naming from the first `terraform apply`. Keeps the existing database as a personal sandbox / playground, clearly quarantined from project work. Slightly more objects in the account.

## Decision

Chose **create fresh `ANALYTICS_DEV`**. Clean conventions from line one of the first Terraform module matter more than avoiding one extra database. The existing `FSP_DATA_INTEGRATION_DB` remains as an untouched scratch area — explicitly out of scope for Terraform management.

## Consequences

- Terraform will not touch `FSP_DATA_INTEGRATION_DB` — it must never appear in any `.tf` file or import block. Any learning artifacts live there, isolated.
- All new schemas (`RAW_<COMPANY_NAME>`, `STAGING`, `CORE`, `MARTS`) go into `ANALYTICS_DEV` in the dev environment, mirrored into `ANALYTICS_PROD` later.
- `.env` already sets `SNOWFLAKE_DATABASE=ANALYTICS_DEV` — consistent.
- When the project is eventually decommissioned, cleanup is a single `terraform destroy` plus a manual drop of `FSP_DATA_INTEGRATION_DB` if desired.
