# Power BI on Snowflake

The legacy-parity serving surface — Power BI semantic model + one paginated
report, both on Snowflake MARTS. Replaces the SSAS Tabular + SSRS pieces
of the old stack. See [ADR-0017](../docs/adr/0017-power-bi-serving.md)
for the design choices (DirectQuery for the model; Import for the
paginated report; key-pair `PBI_SVC` for publish).

## What lives here

| Path | Purpose |
|---|---|
| [walkthrough/01_connect.md](walkthrough/01_connect.md) | Power BI Desktop → Snowflake (OAuth, build phase) |
| [walkthrough/02_semantic_model.md](walkthrough/02_semantic_model.md) | Tables, relationships, measures, hierarchies |
| [walkthrough/03_paginated_report.md](walkthrough/03_paginated_report.md) | Power BI Report Builder — monthly advisor commission statement |
| [walkthrough/04_publish.md](walkthrough/04_publish.md) | Switch to `PBI_SVC` service identity for publish |
| `screenshots/` | Empty until the GUI work happens; populate as you go |
| `fsp_marts.pbix` | Semantic model (binary, committed once built) |
| `fsp_advisor_commissions.rdl` | Paginated report definition (XML, diff-able) |

## Snowflake side (already provisioned via Terraform)

| Object | Purpose |
|---|---|
| `BI_WH` (XSMALL, 60s auto-suspend) | Compute for both Power BI surfaces |
| `RM_BI_WH` (2 credits/month) | FinOps cap — will trip under stress; that's the demo |
| `FR_ANALYST` role | Read-only on STAGING/CORE/MARTS; USAGE on `BI_WH` |
| `LSILINDA` user | Holds `FR_ANALYST` — used during build phase via OAuth |
| `PBI_SVC` user (key-pair) | Service identity for the published model. Default role `FR_ANALYST`, default warehouse `BI_WH`. Public key registered via Terraform; private key at `C:/Users/Lonwabo_Eric/.snowflake/keys/pbi_svc_rsa_key.p8` |

No Snowflake changes are needed during the build phase — `LSILINDA` already
has everything required. `PBI_SVC` only matters at publish time.

## Semantic model design (target)

**Tables (DirectQuery, all from `ANALYTICS_DEV.MARTS`):**
- `finance_advisor_commissions_monthly`
- `portfolio_aum_monthly`
- `risk_policy_inforce`

**Plus conformed dims (DirectQuery, `ANALYTICS_DEV.CORE`):**
- `dim_advisor`, `dim_product`, `dim_fund`, `dim_date`, `dim_client`, `dim_policy`

**Relationships (single-direction, many-to-one fact → dim):**
- `finance_advisor_commissions_monthly[advisor_sk]` → `dim_advisor[advisor_sk]`
- `finance_advisor_commissions_monthly[date_sk]` → `dim_date[date_sk]`
- `portfolio_aum_monthly[client_sk]` → `dim_client[client_sk]`
- `portfolio_aum_monthly[fund_sk]` → `dim_fund[fund_sk]`
- `portfolio_aum_monthly[date_sk]` → `dim_date[date_sk]`
- `risk_policy_inforce[policy_sk]` → `dim_policy[policy_sk]`
- `risk_policy_inforce[advisor_sk]` → `dim_advisor[advisor_sk]`

**Measures (DAX, model-level):**

| Measure | Definition |
|---|---|
| `Total Net Commission` | `SUM(finance_advisor_commissions_monthly[net_commission_amount])` |
| `Avg Commission per Advisor` | `DIVIDE([Total Net Commission], DISTINCTCOUNT(dim_advisor[advisor_sk]))` |
| `Total AUM` | `SUM(portfolio_aum_monthly[market_value_amount])` |
| `Active Policies` | `CALCULATE(DISTINCTCOUNT(risk_policy_inforce[policy_sk]), risk_policy_inforce[is_inforce] = TRUE)` |
| `MoM Commission Δ` | `[Total Net Commission] - CALCULATE([Total Net Commission], DATEADD(dim_date[date], -1, MONTH))` |

**Hierarchy:** `dim_date` → Year > Quarter > Month.

**No calculated columns.** Anything derived lives in dbt models (project rule).

## Cost expectations

DirectQuery hits `BI_WH` on every interaction. Under demo workload:
- ~5–10 credits/month expected
- `RM_BI_WH` caps at 2 credits/month — **the cap will trip during demos**
- That's the FinOps demonstration; the trip is expected behavior

The Import-mode paginated report is one render per parameterized run —
near-zero credits.

## What's NOT here (deferred)

- **Snowflake Semantic Views** — server-side semantic layer. Stretch goal
  (would land as ADR-0018 if added). See ADR-0017 §1.
- **dbt Semantic Layer** — dbt Cloud only; out of scope.
- **Microsoft Entra service principal auth** — `PBI_SVC` key-pair is
  the v0.3.0 answer. See ADR-0017 §3 reversal triggers.
- **Power BI workspace governance, refresh schedules, RLS through Power
  BI** — RLS is delivered via Snowflake row access policies in
  v0.4.0-govern. One governance layer, not two.
- **Multiple paginated reports** — one (advisor commission statement)
  demonstrates the SSRS replacement pattern. Add more if portfolio
  rehearsal demands it.

## Status

- [x] Snowflake side (Terraform): `PBI_SVC` user + `FR_ANALYST` grant
  applied 2026-04-22.
- [x] Walkthrough docs written.
- [ ] Build the .pbix — Power BI Desktop, follow `walkthrough/`.
- [ ] Build the .rdl — Power BI Report Builder, follow `walkthrough/03`.
- [ ] Capture screenshots into `screenshots/`.
- [ ] Commit `.pbix` + `.rdl` + screenshots; tag `v0.3.0-serve`.
