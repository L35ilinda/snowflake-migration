# ADR-0002: Azure remote state backend

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

Terraform state must live somewhere. For solo portfolio work a local `terraform.tfstate` on disk is the minimum-friction option. For realistic enterprise practice (and to demonstrate it in the portfolio writeup), remote state with locking is the right answer.

An Azure storage account (`fspsftpsource`) already exists in the project's resource group, so an Azure Blob backend is one `az cli` call away.

## Options considered

1. **Local state** — zero setup. No locking. Easy to lose. Fine for a throwaway project; embarrassing in a portfolio.
2. **Terraform Cloud (free tier)** — managed remote state, free for small teams. Introduces another SaaS account and auth story that isn't part of the architecture being demonstrated.
3. **Azure Blob backend** — state in a dedicated `tfstate` container in the existing storage account. Uses native Azure locking via blob lease. One-time bootstrap step. Matches the rest of the stack (Azure-native infra) and makes for a clean story in the writeup.

## Decision

Chose **Azure Blob backend** in a dedicated `tfstate` container within the existing `fspsftpsource` storage account. Creates a clean bootstrap narrative and keeps the toolchain Azure-native.

## Consequences

- A one-time bootstrap is required: create the `tfstate` container (via `az cli` or a separate `terraform/bootstrap/` root using local state). Document the bootstrap in the log and in `terraform/README.md`.
- State file holds sensitive data (Snowflake account name, object IDs, occasionally secrets marked `sensitive = true`). Blob container must be private; access via Azure RBAC only.
- State-locking relies on Azure blob leases — generally reliable, but failed Terraform runs can leave stale leases that must be broken manually.
- When `envs/prod/` is added later, it gets its own state key in the same container (e.g. `envs/dev/terraform.tfstate`, `envs/prod/terraform.tfstate`).
