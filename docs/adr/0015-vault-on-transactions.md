# ADR-0015: Data Vault 2.0 on transactions, alongside the star schema; Type 2 dim_policy via dbt snapshot

- **Status:** accepted
- **Date:** 2026-04-22
- **Deciders:** Eric Silinda

## Context

CLAUDE.md §1 commits the project to demonstrating both Star Schema *and*
Data Vault 2.0 modeling. Star Schema is shipped (6 dims + 4 facts in CORE,
3 marts on top). Vault is the missing pillar.

Two open decisions sat in §8: (1) which CORE domain to model as Vault, and
(2) how to convert `dim_policy` from Type 1 to true Type 2.

## Options considered — Vault domain

1. **Policies.** Master data — natural hubs (policy, client, advisor),
   stable business keys, low change rate. *Cons:* low change rate also
   means the Vault story is mostly about "we built it" rather than "we
   tracked history that mattered."

2. **Commissions.** Transactional, financial. *Cons:* simple shape — one
   commission has one policy, one advisor. Doesn't show off links.

3. **Transactions.** *Chosen.* Most history complexity in the model:
   - Two universes (RISK + INVESTMENT) with different attribute sets
   - Multiple FK relationships per row (policy + client + fund + date)
   - Real-life transactions get reversed, restated, status-updated — sat
     change-tracking is meaningful even on static seed data
   - The conformed `fct_transactions` already does the universe union
     work, so Vault models can read from it without re-traversing staging

4. **Valuations.** Time-series-ish, period-snapshot data. *Cons:* less
   linking complexity than transactions; the value-add over current
   `fct_valuations` is marginal.

## Options considered — Type 2 dim_policy

| Approach | Verdict |
|---|---|
| **A. In-place rebuild** — refactor `dim_policy.sql` to read from snapshot, all four `fct_*` join paths get `where is_current = true` | Rejected — surface-area change to four facts for portfolio-grade benefit only |
| **B. Parallel `dim_policy_history`** — keep `dim_policy.sql` as current state; add a new history view over the snapshot | **Chosen** — zero impact on facts; demonstrates the snapshot pattern; matches the common real-world "current dim + history view" split |

## Decisions

### Vault — domain = transactions

Build a complete one-domain Vault (4 hubs, 3 links, 2 sats) under
`dbt/models/core/vault/`:

```text
Hubs                          Business key
  hub_transaction             (company, transaction_id)
  hub_policy                  (company, policy_number)
  hub_client                  (company, client_id_number)
  hub_fund                    (company, fund_code)

Links
  lnk_transaction_policy      hub_transaction × hub_policy
  lnk_transaction_client      hub_transaction × hub_client
  lnk_transaction_fund        hub_transaction × hub_fund

Satellites
  sat_transaction_details     descriptive (type, date, status, narrative,
                              claim_*) — low churn
  sat_transaction_amounts     measures (amount, units, price_per_unit) —
                              higher churn
```

### Vault — split satellites by rate of change

`sat_transaction_details` carries metadata that rarely changes
post-creation; `sat_transaction_amounts` carries financial measures that
can be restated. Keeping them separate is the canonical Vault pattern —
sats are split by "delta velocity" so a change in one column set doesn't
force re-versioning of unrelated columns. Costs slightly more storage in
exchange for cleaner change-tracking semantics.

### Vault — source = `fct_transactions`, not staging

`fct_transactions` already does the RISK + INVESTMENT universe union and
the deduplication. Reading Vault models from there preserves a single
conformance pass and keeps Vault DRY against future staging changes. The
trade-off — Vault is now logically "downstream of star" rather than its
canonical position as "the conformed layer" — is acceptable here because
star is the primary serving model and Vault is the demonstration model.
In a real Vault-first project, both would read from staging directly.

### Vault — materialization

Insert-only is the canonical Vault discipline. Two patterns in play:

- **Hubs and links** — `materialized='incremental'`, `unique_key=<hk>`,
  default `merge` strategy with a `not in (select <hk> from {{ this }})`
  guard in the SQL so re-runs are no-ops on existing keys. New keys
  insert; existing rows are never touched.
- **Satellites** — `materialized='incremental'`,
  `incremental_strategy='append'`, with a **hashdiff guard** in the
  model body. The model computes an MD5 over the attribute payload, joins
  to the latest version per `<hub>_hk` already in the sat, and inserts
  only when the hashdiff differs (or the key is new). This is the
  canonical sat pattern — `merge` is wrong for sats because sats are
  versioned, not updated. Without the hashdiff guard a daily run would
  duplicate every row every day.

The CSVs are static so subsequent runs are no-ops on hubs and links, and
hashdiff-suppressed inserts on sats — fine for the pattern demo. Will
become substantive when source data starts changing (e.g. Airbyte → RAW_OPS
in v1.1.0).

### Vault — naming = `*_hk` for hash keys

Star schema uses `*_sk` (surrogate key). Vault gets `*_hk` (hash key) to
make the modeling style obvious from the column name and avoid implying
the two are interchangeable. Both are computed via
`dbt_utils.generate_surrogate_key` for consistency with existing code.

### Vault — coexistence with star schema

Both stay live. Star is the serving model (facts FK to dims, marts read
facts). Vault is the demonstration model (hubs/links/sats live in
`CORE.VAULT_*` or just `CORE.HUB_*` / `LNK_*` / `SAT_*` per Vault
naming). They share underlying CORE conformance but expose different
modeling surfaces. The portfolio writeup compares them.

### dim_policy — Type 2 via `dbt snapshot` + parallel history view

- New `dbt/snapshots/snp_dim_policy.sql` snapshots `ref('dim_policy')`
  using the **`check`** strategy. `check_cols` is a curated attribute
  set (status, sum_assured columns, premium columns, commission_rate,
  product_name, member_id, smoker_status, age_next, income_bracket,
  advisor) — explicit list rather than `all` so trivial column shuffles
  don't manufacture history rows.
- Snapshot lives in CORE schema in whichever target the build runs
  against — `target_database=target.database`,
  `target_schema=(env_var('DBT_SCHEMA_PREFIX','') ~ 'CORE') | upper` so
  the same definition works in dev (`ANALYTICS_DEV.CORE`) and in CI
  (`ANALYTICS_CI.PR_<n>_CORE`).
- New `dbt/models/core/dim_policy_history.sql` reads from the snapshot
  and projects Type 2 attributes: `valid_from = dbt_valid_from`,
  `valid_to = coalesce(dbt_valid_to, '9999-12-31')`,
  `is_current = (dbt_valid_to is null)`.
- Existing `dim_policy.sql` is **untouched** — facts continue to join to
  current state. Anyone wanting Type 2 history queries
  `dim_policy_history`.

## Consequences

- **New tag target:** `v0.2.0-model-the-warehouse`. Past sessions had
  `v0.2.0-replicate-sources` planned; ADR-0014 retired that scope.
- **New folder:** `dbt/models/core/vault/` — keeps the 9 Vault models
  separate from dims/facts visually.
- **New folder:** `dbt/snapshots/` — referenced from
  `dbt_project.yml` via `snapshot-paths: ["snapshots"]`.
- **Snapshot in CI:** `dbt build --target ci` runs snapshots too. First
  CI run after this change will materialize `SNP_DIM_POLICY` in
  `PR_<n>_CORE` and tear it down on PR close (existing teardown
  workflow). Acceptable cost (~1 second per run on `TRANSFORM_WH`).
- **No fact-table changes.** All existing `fct_*` models continue to
  reference `dim_policy` (Type 1). Joins unchanged.
- **Tests:** uniqueness on every `*_hk`, not_null on hub natural keys,
  `relationships` from each link FK to its hub, composite uniqueness on
  `(hub_hk, load_dts)` for sats. Documented in `_vault__models.yml`.
- **Cost:** ~30s incremental build for the 9 Vault models on first run;
  ~5s thereafter (no-op MERGEs). Snapshot adds one MERGE per run.
  Negligible against `RM_TRANSFORM_WH` 3-credit cap.

## Known limitations / honest gaps

- **Static source data means the Vault history demonstration is dormant
  until Airbyte (v1.1.0) starts feeding changes.** Acknowledged. The
  models are architecturally correct; they just won't have meaningful
  sat versions to query against until source data starts changing.
- **Vault reading from `fct_transactions` rather than staging** is a
  pragmatic shortcut — see "Vault — source" above. Documented so the
  portfolio writeup can call it out as a deliberate trade-off.
- **`check` strategy on snapshot** vs `timestamp`: `dim_policy._loaded_at`
  is monotonically increasing per row but not necessarily per business
  key — same policy can have multiple `_loaded_at` values across
  re-loads of the source CSV. `check` is the safer choice here.
- **Sat first-run "everything new" inserts** are expected — the guard
  catches no-op re-runs but the very first run inserts one row per
  transaction (~100K per sat). Acceptable.
