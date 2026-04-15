# ADR-0001: Modular Terraform layout

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

The project will provision Snowflake and Azure resources via Terraform: storage integrations, stages, file formats, pipes, RBAC, warehouses, resource monitors, databases/schemas, and masking policies. It is explicitly built to enterprise standards as a Snowflake Solution Architect portfolio piece.

Two layout patterns were on the table:
1. **Flat** — all `.tf` files in `terraform/` root (`providers.tf`, `stages.tf`, `rbac.tf`, ...).
2. **Modular** — reusable modules under `terraform/modules/<name>/` called from per-environment roots under `terraform/envs/<env>/`.

## Options considered

1. **Flat layout** — minimum boilerplate, fast to start. Adequate for a single-environment hobby project. Breaks down when adding `prod` or sharing modules.
2. **Modular layout (per-env root)** — modules/ holds reusable units; envs/dev/ and envs/prod/ compose them. More scaffolding upfront. Matches the project's stated convention ("modules for anything reused") and is the realistic pattern for a Solution Architect portfolio.

## Decision

Chose **modular layout**. The whole point of this project is to demonstrate enterprise Terraform practice. A flat layout would be a red flag in an interview review. Slightly more setup now pays for itself the moment a second environment is added.

## Consequences

- Higher day-one file count and some duplication between `envs/dev` and `envs/prod` (acceptable — explicit is better than implicit for env config).
- Modules must be designed for reuse: no hardcoded names, all inputs via `variables.tf`, all outputs explicit.
- A separate `envs/dev/` root means `terraform init` / `plan` / `apply` must be run from that directory, not the repo root. Document in README once first module lands.
