# ADR-0017: Power BI on Snowflake — semantic model location, connection mode, and auth

- **Status:** accepted; **publish step skipped + GUI build deferred — see 2026-04-22 addenda**
- **Date:** 2026-04-22
- **Deciders:** Eric Silinda

> **2026-04-22 addendum #2 — GUI build deferred to post-v1.0** (see
> [ADR-0018](0018-defer-power-bi-gui-build.md)). The `.pbix` and `.rdl`
> GUI builds and screenshots move to a parked bullet. `v0.3.0-serve` is
> declared done at design+scaffold scope (no separate git tag — same
> convention as Replicate Sources at 3-tenant scope per ADR-0014).
> Streamlit-in-Snowflake remains the live serving surface; ADR-0017
> §1 + §2 design decisions stay canonical for whenever the GUI work
> resumes. Walkthroughs in [power_bi/walkthrough/](../../power_bi/walkthrough/)
> are the canonical instructions for that future work.

> **2026-04-22 addendum #1 — publish skipped.** The `.pbix` and `.rdl`
> ship in the repo + screenshots only; nothing is published to a
> Power BI Service workspace. Consequences:
>
> - **`PBI_SVC` Snowflake user destroyed.** It existed solely as the
>   service identity for the published-model connection; with publish
>   skipped, it has no purpose. Removed from Terraform; private/public
>   keys at `C:/Users/Lonwabo_Eric/.snowflake/keys/pbi_svc_rsa_key.{p8,pub}`
>   left on disk for the user to delete manually if desired.
> - **Build phase still uses OAuth as `LSILINDA`** — unchanged.
> - **`walkthrough/04_publish.md` deleted** (dead instructions).
> - **Reversal:** if publish becomes necessary later, the §3 publish-phase
>   decisions in this ADR remain canonical — re-add `PBI_SVC` (or adopt
>   the Microsoft Entra reversal trigger) at that point.
> - The §1 (semantic model in Power BI) and §2 (DirectQuery + Import)
>   decisions are unaffected.

## Context

CLAUDE.md §1 commits the project to demonstrating the legacy stack
replacement narrative: "SSAS Tabular → Power BI semantic model" and
"SSRS Report Server + subscriptions → Power BI Paginated Reports +
subscriptions." `v0.3.0-serve` is the milestone that delivers this.

Streamlit-in-Snowflake is already live (4 dashboards over MARTS,
[ADR-0011](0011-cortex-analyst-deferred.md) deferral). That covers the
"native serving" surface. Power BI is the legacy-parity surface — the
artifact a stakeholder migrating off SSAS would actually receive.

Three decisions to nail down before building anything:

1. **Where does the semantic model live?** Power BI / Snowflake Semantic
   Views / dbt Semantic Layer — this was an open question in
   CLAUDE.md §8.
2. **Connection mode** — Import / DirectQuery / Hybrid.
3. **Authentication** — interactive OAuth / service principal / Snowflake
   key-pair user.

## Decisions

### 1. Semantic model lives in Power BI for v0.3.0

Picked **Power BI semantic model** (Tabular model in the .pbix file).

Rejected for v0.3.0:

- **Snowflake Semantic Views** — Snowflake's first-party server-side
  semantic layer (SQL `CREATE SEMANTIC VIEW`). The cleaner enterprise
  pattern: define metrics once in Snowflake, every consumer (Power BI,
  Tableau, Cortex Analyst, ad-hoc SQL) sees the same definitions.
  Stronger SA story than Power-BI-only. **Flagged as v0.3.x stretch**;
  not v0.3.0 critical path because it adds a second tool to learn while
  the goal here is the SSAS-replacement narrative. Will land as ADR-0018
  if we add the stretch.
- **dbt Semantic Layer** — dbt Cloud only. Project is on dbt Core
  (ADR — `dbt Core over Cloud` is implicit in CLAUDE.md §3 tooling).
  Adopting dbt Cloud just for the Semantic Layer is a multi-hundred-USD/
  month subscription expansion for a portfolio project. Hard no.

### 2. DirectQuery for the semantic model; Import for the paginated report

| Surface | Mode | Why |
|---|---|---|
| Semantic model (.pbix) | **DirectQuery** | Every interaction pushes down to Snowflake — strongest demonstration of the warehouse-native pattern. Analysts get live data without scheduled refreshes. Cost is bounded by `RM_BI_WH` 2-credit/month cap (caps are part of the demo). |
| Paginated report (.rdl) | **Import** | A paginated report renders once per parameterized run (`render advisor X for month Y`). Import keeps `BI_WH` from spinning up on every preview. Acceptable freshness because monthly statements are inherently snapshotted at month-end. |

DirectQuery has known footguns (no certain DAX patterns, no
calculated columns on date dims, slow on huge fact joins). Mitigated by:

- The marts are pre-aggregated (`finance_advisor_commissions_monthly`,
  `portfolio_aum_monthly`, `risk_policy_inforce`) — fact joins are
  small, sub-second on XS warehouse.
- The conformed CORE dims are themselves small (~6 dims, low cardinality).
- Calculated columns kept to zero — all derived fields live in dbt
  models, Power BI surfaces them as-is. (Project rule: derive in SQL,
  not in Power BI.)

Hybrid mode (Import for dims, DirectQuery for facts) is the "production"
answer at scale but adds complexity and isn't required for the demo.

### 3. Auth: interactive OAuth for build, service principal + key-pair for publish

Two roles for two phases:

- **Build phase** (developer iterating on the .pbix in Power BI Desktop):
  **OAuth (Snowflake browser SSO)** as `LSILINDA`. Avoids a service-user
  registration loop just to start building. `LSILINDA` already has
  `FR_ANALYST`, so the model sees only what an analyst would see.
- **Publish phase** (the published `.pbix` running on a schedule or
  serving end users): **`PBI_SVC` service user with key-pair auth**.
  Matches the existing separation-of-identity pattern (`CI_SVC` for
  GitHub Actions, `AIRBYTE_SVC` for replication — both use key-pair per
  ADR-0009 / ADR-0013). `PBI_SVC` is granted only `FR_ANALYST`. Read-only
  on staging/core/marts; never anything else.

Microsoft Entra service principal + Snowflake OAuth integration is the
"true production" answer (no shared key, audit per-app). Rejected for
v0.3.0: requires an Azure AD app registration + Snowflake Security
Integration roundtrip, which is real work for a portfolio project where
the key-pair pattern is already proven and audited.

## Consequences

- **New Snowflake objects via Terraform:**
  - `PBI_SVC` user with key-pair auth, `default_role = FR_ANALYST`,
    `default_warehouse = BI_WH`. Same Terraform pattern as `CI_SVC` /
    `AIRBYTE_SVC`.
  - Out-of-module grant: `FR_ANALYST` to `PBI_SVC` (matches
    `airbyte_svc_fr_airbyte` precedent).
  - **No schema or warehouse changes** — `FR_ANALYST` already has RO on
    STAGING/CORE/MARTS and USAGE on `BI_WH`.
- **New repo dir:** `power_bi/` containing:
  - `README.md` — connection setup, semantic model design, measures list.
  - `walkthrough/01_connect.md` → `04_publish.md` — step-by-step for the
    GUI work (Power BI Desktop and Report Builder).
  - `screenshots/` — empty placeholder; gets filled in as the GUI work
    happens.
  - `fsp_marts.pbix` (binary, committed once built) — the semantic model.
  - `fsp_advisor_commissions.rdl` (Report Builder source, XML-ish — diff-able).
- **One paginated report** for v0.3.0: monthly advisor commission
  statement. Parameterized by `advisor_identifier` and `month`. Mirrors
  the typical SSRS subscription artifact.
- **Cost ceiling:** DirectQuery on the semantic model uses `BI_WH`. At
  XS auto-suspend 60s, expect 5–10 credits/month under demo workload.
  `RM_BI_WH` caps at 2 credits/month — the cap will trip under
  stress-test, which is the FinOps demonstration. Document the trip as
  expected behaviour in the README.
- **Power BI Pro license** ($14/user/month) required to publish to a
  workspace. **Not required for v0.3.0** — `.pbix` lives in the repo,
  screenshots tell the story for the portfolio writeup.
- **No Power BI workspace governance, refresh schedules, RLS through
  Power BI** — multi-tenant row-level security is delivered via
  Snowflake row access policies in v0.4.0-govern, not Power BI RLS. One
  governance layer, not two.
- **`PBI_SVC` private key** lives outside the repo at
  `C:\Users\Lonwabo_Eric\.snowflake\keys\pbi_svc_rsa_key.p8`. Public key
  registered on the Snowflake user via Terraform (same pattern as
  `CI_SVC` / `AIRBYTE_SVC`).

## Reversal triggers

Promote Snowflake Semantic Views into v0.3.x if any of:

- The portfolio writeup rehearsal exposes "Power BI is the only place
  metrics are defined" as a weak SA story.
- A second consumer (Tableau, Cortex Analyst, ad-hoc) needs the same
  metrics — second definition is the trigger.
- Snowflake Semantic Views graduates from preview to GA in
  `AZURE_EASTUS` (currently preview-only in many regions).

Promote Microsoft Entra service principal auth if any of:

- Multiple Power BI workspaces or apps need to authenticate as
  distinguishable identities.
- A real shared-credential rotation policy enters scope (e.g. portfolio
  becomes a real consulting engagement).
