# FSP Analyst — Streamlit in Snowflake

Per-domain dashboards and a SQL playground over the MARTS layer, running as a Snowflake-native Streamlit app.

> **Cortex Analyst NL-to-SQL is deferred.** The project's Snowflake account is in `AZURE_EASTUS`, which Cortex Analyst does not yet support. All Cortex scaffolding (semantic model YAML, RBAC grants, account enablement flag) stays in place — re-enabling is a one-file change in `app/streamlit_app.py` if the account ever moves to a supported region. See [ADR-0011](../docs/adr/0011-cortex-analyst-deferred.md).

## Architecture (current)

```
User (FR_ENGINEER or FR_ANALYST) in Snowsight
  → Streamlit app (Snowflake-native, runs on BI_WH)
    → session.sql(...) directly against MARTS tables
    → pandas DataFrame rendered in UI
```

## Architecture (Cortex-ready, deferred)

```
User (FR_ANALYST) in Snowsight
  → Streamlit app (Snowflake-native, runs on BI_WH)
    → Cortex Analyst REST API (/api/v2/cortex/analyst/message)
      ← semantic model YAML on @ANALYTICS_DEV.SEMANTIC.MODELS
      ← MARTS tables for grounding
    → generated SQL executed via active Snowpark session
    → pandas DataFrame rendered in UI
```

## Files

- `app/streamlit_app.py` — chat UI, Cortex call, SQL execution
- `app/environment.yml` — Snowflake-managed Python env (streamlit, pandas, snowpark)
- `semantic_model/fsp_marts.yaml` — dimensions, measures, synonyms, verified queries

## What the semantic model covers

Three marts, tenant-aware (MAIN_BOOK / INDIGO_INSURANCE / HORIZON_ASSURANCE):

| Table in model | Source mart | Purpose |
|---|---|---|
| `advisor_commissions_monthly` | `MARTS.FINANCE_ADVISOR_COMMISSIONS_MONTHLY` | Commission performance by advisor / month / category |
| `aum_monthly` | `MARTS.PORTFOLIO_AUM_MONTHLY` | AUM trends by fund / month |
| `policy_inforce` | `MARTS.RISK_POLICY_INFORCE` | In-force risk book by status / demographic |

Each table has dimensions, time dimensions, measures with aggregation hints, synonyms, and three verified example queries to ground Cortex on expected patterns.

## Deployment

All infrastructure is managed by Terraform (`terraform/modules/snowflake_streamlit_analyst`). Files on the stage are managed out-of-band via `scripts/upload_streamlit_app.py`.

```bash
# First-time or after semantic-model / app changes:
python scripts/upload_streamlit_app.py
```

After upload, open Snowsight → Streamlit → `FSP_ANALYST` → Run.

## Example questions

- "Who were the top 10 advisors by net commissions in 2024?"
- "Show monthly AUM trend for Main Book in 2024."
- "What's the lapse rate per tenant?"
- "Which funds had the highest month-on-month growth in December 2024?"
- "Compare annualised premium by smoker status for Horizon Assurance."

## Known limitations (carry-over)

- Single-turn UI: chat history is preserved in session state but not persisted across sessions.
- No custom chart rendering — results are tables only.
- Cortex Analyst has per-message pricing; not a concern at demo scale.
- Semantic model + marts must stay in sync manually.
