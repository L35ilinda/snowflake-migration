# ADR-0008: Keep the STAGING layer between RAW and CORE

- **Status:** accepted
- **Date:** 2026-04-19
- **Deciders:** Eric Silinda

## Context

The project's layer model is `RAW_<COMPANY>` → `STAGING` → `CORE` → `MARTS`. During Foundations we built 6 dbt staging views for Main Book. The question surfaced while planning Replicate Sources: why keep STAGING at all? Why not transform directly from RAW into dimensional models (Star Schema) and Data Vault targets in CORE?

This is a legitimate question. Extra layers cost compile time, cognitive load, and create more objects to explain in the writeup. The question deserves an explicit answer, not a default.

Terminology note: RAW in this project **is** the landing table. Snowpipe writes directly to `RAW_<COMPANY>.<DATASET>` (all-VARCHAR, `ON_ERROR = CONTINUE`). There is no separate "landing" layer above RAW.

## Options considered

1. **RAW → CORE directly.** Skip the staging views. Type casting, column renaming, and per-source cleaning happen inside fact and dimension models (or Vault hubs/links/sats). Fewer objects. One less layer to explain.
2. **RAW → STAGING → CORE.** A thin per-source layer of views that cast types, rename columns, and normalize per-source quirks. CORE consumes conformed, source-shape-aligned views. This is the dbt community convention.

## Decision

Chose **RAW → STAGING → CORE**. STAGING stays.

## Rationale

Four concrete reasons the layer pays for itself on this project:

1. **Conformance across tenants.** Three companies with deliberately non-standardized schemas. `main_book_risk_benefits` is PascalCase. `indigo_insurance` is snake_case. `horizon_ins_commissions` may differ again. Normalizing per-source quirks inside fact/dim models forces every fact to contain a per-source union or case statement. STAGING normalizes the shape before CORE sees it. Conformance is a staging concern, dimensional modeling is a CORE concern; separating them keeps both models readable.

2. **Replay-ability.** RAW is append-only. When a fact has a bug, the fix is a dbt change plus a rebuild from RAW — no re-ingestion from Azure. If casting and conformance live inside the fact, a schema-level fix may require reloading or altering immutable state. Staging preserves the ingest boundary.

3. **Testing boundary.** Staging tests catch **source drift** — new NULLs, type changes, renamed columns, unexpected values. CORE tests catch **business logic bugs** — bad joins, wrong grain, broken conforming rules. If the two responsibilities collapse into one layer, a failing test does not tell you whether the source drifted or the logic is wrong. The boundary is cheap and diagnostically valuable.

4. **Debugging trail.** When a dimension value looks wrong in a dashboard, the investigation walks back through layers: is the dim wrong, is the fact wrong, is staging misaligned, or did the source change? Each layer provides an intermediate artifact to query. Collapsing layers removes the traceback.

## Consequences

- STAGING materializes as views (`+materialized: view` in `dbt_project.yml`). Zero storage cost; only compile-time CPU when queried by downstream models.
- Every RAW table has a corresponding `stg_<company>__<dataset>.sql` that casts types and renames columns. This is mechanical but explicit.
- CORE models read from `ref('stg_...')` exclusively, never from sources. This is enforced by dbt convention and caught in review.
- One more layer of models to maintain. Acceptable cost for the benefits above.
- If a future phase ingests a clean, schema-validated source (e.g., a Protobuf-typed Kafka topic), that source's staging layer can be a pass-through (`select * from source`) or skipped with explicit justification. Default stays "keep staging."

## Related

- ADR-0006: Named RAW schemas over numeric tenant suffixes — established the per-tenant RAW pattern that STAGING conforms.