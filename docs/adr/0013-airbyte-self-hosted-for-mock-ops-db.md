# ADR-0013: Airbyte (self-hosted) for replicating mock operational DB to Snowflake

- **Status:** accepted; **implementation deferred to v1.1.0 per ADR-0014 (2026-04-22)**
- **Date:** 2026-04-21
- **Deciders:** Eric Silinda

> **Deferral note (2026-04-22):** The *choice* documented here — Airbyte
> self-hosted over Fivetran / Airbyte Cloud / roll-our-own / Snowpipe-from-CSV —
> is unchanged. Only the *timing* moved. The Snowflake-side scaffolding
> (`RAW_OPS` schema, `AIRBYTE_SVC` user, `FR_AIRBYTE` role) and the
> `mock_ops_db/` Docker reference remain in place. Phase B (Airbyte deploy +
> first sync + dbt staging on `RAW_OPS`) ships in **v1.1.0**, after the v1.0.0
> portfolio-ready milestone. See [ADR-0014](0014-defer-airbyte-and-queue-onboarding.md)
> for the full sequencing rationale. The hosting decision (managed Azure
> Postgres Flexible Server, not local Docker) lands in a separate ADR when
> v1.1.0 work resumes.

## Context

The Replicate Sources phase needs a non-file ingestion path to demonstrate
the full "operational DB → analytics warehouse" leg of the legacy stack
replacement. The legacy stack used SQL Server as a virtualization layer over
operational systems plus Ab Initio for scheduled ETL. The target stack
replaces that with managed CDC into Snowflake.

To exercise this, we need:
1. A mock operational database (Postgres in local Docker — synthetic data,
   doesn't need to be production-shaped).
2. A replication tool that lands its tables into a `RAW_OPS` schema in
   `ANALYTICS_DEV` on a schedule, ideally with CDC.

This ADR picks the replication tool. The mock DB itself is a one-line decision
(Postgres, Docker, seed SQL — no architectural debate).

## Options considered

1. **Fivetran.** Industry standard for managed CDC into Snowflake. SaaS,
   subscription-priced (~$120/mo at the smallest tier when you actually move
   data; free tier is 0.5M MAR which would cover our scale). Pros: zero
   operational burden, broadest connector catalog, the tool data engineers
   evaluate by default. Cons: subscription model even at free tier requires
   credit card; less hands-on learning since the connectors are black boxes;
   not what a Solution Architect builds at home.

2. **Airbyte Cloud.** Managed Airbyte. Free tier with credit volume cap. Pros:
   same Airbyte connector catalog as self-hosted, no infra. Cons: again
   black-box; a portfolio project specifically demonstrating SA capability is
   weakened by "I clicked a button in Airbyte Cloud."

3. **Airbyte self-hosted (Docker / abctl).** Run Airbyte locally via the
   official Docker quickstart or `abctl` CLI; configure source (Postgres) and
   destination (Snowflake) connectors via the UI or octavia-cli. Pros: $0
   cost, full visibility into how the tool actually works (Temporal workflows,
   per-connector containers, normalization), demonstrates the operational
   side of running the tool — which is exactly what an SA conversation
   eventually goes to. Cons: real setup overhead (~30-60 min first time);
   resource cost on the laptop; Airbyte's self-hosted deployment story
   changes every ~6 months (`docker-compose` → `abctl` → Helm).

4. **Roll-our-own Python (Snowpark / Snowflake connector).** Write a small
   Python job that polls the Postgres mock and INSERTs into Snowflake on a
   schedule (Airflow or cron). Pros: cheapest to build; full control; total
   transparency. Cons: no portfolio value — every data engineer can write a
   replication script; the Solution Architect role specifically asks "have you
   evaluated the major CDC tools." Loses the entire teaching moment.

5. **Snowflake-native: external table over a CSV dump from Postgres.** Hack:
   `pg_dump` to CSV → Azure container → existing Snowpipe path. Pros: reuses
   the file ingestion infra. Cons: not CDC; not the target architecture's
   intent; demonstrates nothing new.

## Decision

Chose **option 3** — Airbyte self-hosted in local Docker.

Primary reason: this is a portfolio project for a Snowflake Solution Architect
role. The interesting question is not "did you replicate some rows" — it's
"have you stood up Airbyte, made a connector choice between full-refresh and
CDC, configured Snowflake destination credentials with key-pair auth,
debugged a sync failure." Self-hosted is the only option that produces
defensible answers to those questions.

Cost is $0. Operational complexity is real but bounded: Airbyte's Docker
quickstart is `abctl local install` and ~10 GB of disk. Acceptable for the
portfolio scale.

Fivetran would be the right answer in a real consulting engagement. It is
the wrong answer here because the goal is depth-of-knowledge demonstration,
not least-effort replication.

## Consequences

- **New mock-ops surface:**
  - `mock_ops_db/docker-compose.yml` — Postgres 16, exposed locally.
  - `mock_ops_db/seed/` — schema + seed SQL for 2 operational tables
    (`policies_master`, `claims`) with ~10K synthetic rows.
- **New Snowflake objects** (Terraform):
  - `RAW_OPS` schema in `ANALYTICS_DEV` for Airbyte to land its tables into.
  - `AIRBYTE_SVC` user with key-pair auth (separate key from `LSILINDA` and
    `CI_SVC` per ADR-0009 separation-of-identity precedent).
  - `FR_AIRBYTE` functional role aggregating `raw_ops_rw` access role.
  - RBAC integration via the existing `snowflake_rbac` module.
- **dbt:** placeholder source file (`models/staging/ops/_ops__sources.yml`)
  declaring the operational tables as sources. Tagged stale until Phase B
  actually lands the data.
- **Phase split:** Phase A (this session) is everything above. **Phase B**
  (next session) is `abctl local install`, configuring the Postgres source
  and Snowflake destination through the Airbyte UI, running the first sync,
  then writing dbt staging models on the replicated tables.
- **Tool setup loop is interactive.** Airbyte source/destination
  configuration is done in the UI, not in Terraform — there is no first-party
  Airbyte Terraform provider for self-hosted that's worth the maintenance.
  octavia-cli exists for declarative configuration; consider it if Phase B
  reveals a need for source-controlled connector configs.
- **Resource cost on dev laptop:** Airbyte runs Temporal + Postgres + a worker
  pool — expect ~3 GB RAM idle. Stop the stack between sessions.

## Known limitations

- **No CDC for the first sync** — full-refresh is the simplest source mode
  for a mock Postgres without configured replication slots. Upgrade to
  `Logical Replication (CDC)` mode in Phase B once a baseline sync is green.
- **Airbyte version drift.** Self-hosted deployment story is in flux. Pin to
  a specific Airbyte version in `docker-compose.yml` to avoid surprise
  upgrades breaking the Phase B walkthrough.
- **No production parity.** Self-hosted Airbyte is not how the project would
  ship in production — call this out explicitly in the portfolio writeup as
  "Airbyte chosen for hands-on tool exposure; Fivetran or Airbyte Cloud is
  the production-grade equivalent."
