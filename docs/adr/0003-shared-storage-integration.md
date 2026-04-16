# ADR-0003: Single shared storage integration across companies

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

The project is multi-tenant by design — three "companies" with independent data feeds dropped into three Azure storage containers (originally `fsp-company-01/02/03`, later renamed to `fsp-main-book`, `fsp-indigo-insurance`, `fsp-horizon-assurance`). Snowflake storage integrations are the object that binds a Snowflake account to an Azure storage principal; they require a manual consent step in the Azure portal (admin consent for the Snowflake service principal).

The question: one shared storage integration covering all three containers, or one integration per company?

## Options considered

1. **One integration per company.** Stricter blast radius — each integration only sees its company's container. More realistic multi-tenant isolation at the Azure-IAM layer. Requires three separate Azure admin-consent flows (manual portal clicks). Three more Terraform resources to manage.
2. **One shared integration covering all three containers.** Single Azure consent flow. Single Snowflake object. Isolation happens *above* the integration — at the external stage, RBAC, and schema level, where it belongs architecturally anyway. Simpler day-one, no real loss in the security model because stages are where per-tenant access is enforced.

## Decision

Chose **one shared storage integration** listing all three containers in `STORAGE_ALLOWED_LOCATIONS`. Multi-tenant isolation is enforced at the external-stage and RBAC layers, not at the storage integration.

## Consequences

- Only one Azure admin-consent step to perform manually the first time we `terraform apply` the integration.
- Per-company isolation must be rigorous at the stage and schema layers (`STG_<COMPANY_NAME>` stages granted only to the matching access roles). This is the right place for it anyway.
- If one company is later revoked or offboarded, we update `STORAGE_ALLOWED_LOCATIONS` to remove its container and reapply — slightly less clean than destroying a dedicated integration, but a five-line diff.
- The blast radius of a compromised integration credential is all three containers rather than one. Acceptable for a portfolio; call out as a known tradeoff in the writeup. In a real production build for an unrelated-tenants scenario, per-tenant integrations would be the right call.
