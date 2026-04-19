# ADR-0007: Disable SFTP on the Azure storage account

- **Status:** accepted
- **Date:** 2026-04-19
- **Deciders:** Eric Silinda

## Context

The Azure storage account `fspsftpsource` was originally provisioned with SFTP enabled (the name reflects its starting purpose: an SFTP drop target mimicking the legacy landing zone). SFTP required enabling Hierarchical Namespace (HNS/Data Lake Gen2) and local users.

The project has since moved to a pull-based ingestion model:

- Snowflake storage integration `SI_AZURE_FSPSFTPSOURCE_DEV` authenticates via Entra ID and accesses the containers through the Blob REST API over HTTPS.
- Snowpipe uses the storage integration — no SFTP involved.
- Files are staged into the Azure containers via Azure CLI (`az storage copy`) from the developer workstation.

No tool in the current pipeline uses the SFTP endpoint.

## Options considered

1. **Leave SFTP on.** Keeps the "pretend legacy landing zone" story intact if we ever want to demo an SFTP drop. Ongoing cost and an unused attack surface.
2. **Disable SFTP and local users.** Removes ~USD 0.30/hour in SFTP endpoint charges (~USD 216/month if left on continuously) and closes port 22. If SFTP is ever needed for a demo, it can be re-enabled with a single `az storage account update`.

## Decision

**Disable SFTP and local users on `fspsftpsource`.** Keep HNS enabled — required to reverse the decision cheaply, and benign for Snowpipe.

## Rationale

This is a **personal portfolio project using synthetic data**. The priorities are:

- **Cost discipline.** SFTP is priced per-hour per-endpoint, independent of usage. For a portfolio that may run for months between work sessions, an always-on SFTP endpoint is pure burn. Portfolio projects should demonstrate FinOps awareness, not generate avoidable spend.
- **No production workload depends on SFTP.** Disabling it has zero impact on the Snowflake → dbt pipeline.
- **Security is a secondary benefit.** Fewer open endpoints, no local-user credentials to manage. Relevant for the writeup but not the primary driver here.

If a future phase genuinely needs an SFTP-driven drop pattern (e.g., demonstrating the Connect:Direct-to-Snowpipe narrative end to end), SFTP can be re-enabled in ~30 seconds.

## Consequences

- Port 22 on `fspsftpsource` is closed. SFTP client connections fail.
- Local user accounts are disabled.
- Snowpipe, storage integration, and `az storage` commands continue to work unchanged (verified with `LIST @STG_MAIN_BOOK;` after the change).
- Ongoing cost of the SFTP endpoint → USD 0.
- HNS remains enabled. If ever turned off, the account would need to be recreated — not worth the savings.
- The storage account name `fspsftpsource` is now a historical artifact, not a functional description. Not renaming it; the cost and risk of renaming (storage integration, Terraform state, all stage URLs) far outweighs the cosmetic benefit.