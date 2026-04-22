# ADR-0014: Defer Airbyte+Postgres replication to v1.1.0; lock project scope to 3 tenants

- **Status:** accepted
- **Date:** 2026-04-22
- **Deciders:** Eric Silinda

## Context

Two pieces of in-flight work were originally scoped into `v0.2.0-replicate-sources`:

1. **Onboarding-queue completion.** 8 additional company groups (baobab, fynbos,
   karoo, khoisan, protea, springbok, summit, ubuntu) sitting in
   `fsp-data-onboarding-queue/Outbound/` (48 files), plus 15 shared/reference
   files (accounts, customers, transactions, etc.).
2. **Airbyte+Postgres replication.** A managed Azure Postgres Flexible Server
   acting as mock operational DB, replicated into Snowflake `RAW_OPS` via
   self-hosted Airbyte (ADR-0013), with Flyway managing Postgres DDL.

Both were tagged "needed before v0.2.0." Pausing to ask: **are they actually
needed before v1.0.0?**

## Decision

**Lock the project scope to the 3 existing tenants** (Main Book, Indigo
Insurance, Horizon Assurance) for the entire `v0.x → v1.0.0` arc. Defer
both items above to **v1.1.0**.

Reframe `v0.2.0` away from "replicate sources" and toward what's actually
left to make the warehouse production-grade with the data already loaded.

### Sub-decisions

- **8 queue tenants → parked for manual practice.** The user wants to
  onboard them by hand later as a learning exercise (Snowpipe + dbt
  staging without the assistant doing it). Files stay in
  `fsp-data-onboarding-queue/Outbound/`.
- **Shared/reference files → parked.** Same queue. Placement decision
  (shared `RAW_SHARED` vs per-tenant duplication) deferred until manual
  practice surfaces a real need.
- **Airbyte+Postgres → deferred to v1.1.0.** Tracked as a separate post-1.0
  vertical, not a v1.0 blocker.
- **Provisioned-but-unused objects stay.** `RAW_OPS` schema, `AIRBYTE_SVC`
  user, `FR_AIRBYTE` role were applied at the end of the previous session
  (ADR-0013). They sit empty. Cost ≈ R0 idle. Destroying them now just to
  recreate in v1.1.0 is churn — leave them in place.
- **`mock_ops_db/` Docker scaffold stays as reference.** Schema and seed
  design carry forward to the v1.1.0 Flyway migrations; the
  `docker-compose.yml` stops being the deployment target but remains
  useful for local schema iteration.
- **ADR-0013 stays "accepted"** with a banner noting deferral. Not
  superseded — the *choice* (Airbyte self-hosted) is unchanged; only the
  *timing* moved.

### Roadmap renumbering

| Old | New |
|---|---|
| v0.2.0 Replicate sources (queue + Airbyte) | v0.2.0 **Model the warehouse** |
| v0.3.0 Model the warehouse | v0.3.0 **Serve** (Power BI) |
| v0.4.0 Serve | v0.4.0 **Govern** |
| v0.5.0 Govern | v0.5.0 **Orchestrate + AI** |
| v0.6.0 Orchestrate + AI | v1.0.0 **Portfolio writeup** |
| v1.0.0 Portfolio writeup | v1.1.0 **Replicate operational DB** (Airbyte + Postgres + queue onboarding) |

## Why this is the right call

1. **No hard downstream dependency on `RAW_OPS` data.** dbt snapshots,
   Data Vault on transactions, Power BI semantic model on MARTS, row
   access policies on CORE, Airflow orchestration of the existing
   pipeline, and Document AI demos are all independent of the Airbyte
   data path. Snowpipe-from-CSV already covers ingestion decisively.
2. **Higher-impact work first.** Power BI semantic model + paginated
   reports (the SSAS/SSRS replacement story) and row access policies (the
   multi-tenant governance story) are stronger Solution Architect
   demonstrations than a second ingestion path. Front-loading them maxes
   out portfolio value per session.
3. **Cost.** Azure Postgres Flexible Server B1ms with auto-stop runs
   ~R30–60/day. Deferring across the v0.3 → v1.0 window saves several
   hundred rand for zero capability loss in the interim.
4. **Cleaner narrative.** "v1.0 ships file ingestion + warehouse + serving
   + governance + AI; v1.1 adds operational-DB CDC" reads as deliberate
   phasing. "v1.0 ships everything except the half-built Airbyte vertical"
   reads as unfinished.
5. **Honors a stated user preference.** The 8 queue tenants are explicitly
   parked for manual practice — that's a teaching/learning goal, not a
   delivery goal. Treating them as v1.0 blockers would force me to either
   onboard them for the user (defeats the practice goal) or block v1.0
   indefinitely.

## Consequences

- **`v0.2.0-replicate-sources` tag is abandoned.** Next tag is
  `v0.2.0-model-the-warehouse`.
- **CLAUDE.md updated** in §4 (Pending), §6 (Next milestone), §8 (open
  questions become "deferred"), and §9 (phased roadmap).
- **`v0.2.0` becomes:** `dbt snapshot` for `dim_policy` (Type 1 → Type 2)
  + Data Vault 2.0 domain on transactions (hubs/links/sats alongside the
  existing star schema).
- **Provisioned-but-idle Snowflake objects** (`RAW_OPS`, `AIRBYTE_SVC`,
  `FR_AIRBYTE`) become a known curiosity of the state — anyone reading
  Terraform will see scaffolding for a feature that isn't live yet.
  Mitigated by the comments in `dev/main.tf` and ADR-0013's banner.
- **Portfolio writeup at v1.0** must explicitly call out Airbyte+Postgres
  as "v1.1 next" rather than pretending it's done. Honest framing.
- **No code or data changes** required to enact this decision — purely
  documentation.

## Reversal triggers

Promote v1.1.0 work back into the v1.0 path if any of:

- A specific v0.3–v0.5 task discovers it actually needs operational-DB
  data (no current line of sight to this).
- The portfolio narrative gap proves uncomfortably large in writeup
  rehearsal (low likelihood — Snowpipe ingestion + dbt + serving is a
  full vertical on its own).
- Cost ceases to matter (e.g. a sponsor funds the Postgres burn).