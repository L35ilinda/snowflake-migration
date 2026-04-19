# ADR-0011: Cortex Analyst deferred — Azure East US is not a supported region

- **Status:** accepted
- **Date:** 2026-04-19
- **Deciders:** Eric Silinda

## Context

The plan was to ship a Streamlit-in-Snowflake app backed by Snowflake Cortex Analyst for natural-language Q&A over the MARTS layer. All supporting infrastructure was built: semantic model YAML, internal stage, Streamlit app, RBAC grants, Cortex Analyst account-level enablement, and `SNOWFLAKE.CORTEX_USER` grants to the relevant roles.

First live invocation failed:

```
Cortex Analyst error 400: "Cortex Analyst is not enabled"  → fixed via ALTER ACCOUNT
Cortex Analyst error 404: "tables do not exist or are not authorized" → fixed via role grants
Cortex Analyst error 503: error_code 392704
```

Root-cause investigation: `SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', 'hi')` also failed with an external-function 500. Our Snowflake account is in region `AZURE_EASTUS`. Per the Snowflake Cortex Analyst documentation, the feature is available in:

- AWS: `us-east-1`, `us-west-2`, `eu-central-1`, `ap-southeast-2`, `ap-northeast-1`
- Azure: **`east us 2`**, `west europe`
- GCP: `us-central1`

`AZURE_EASTUS` is not in that list. `East US` and `East US 2` are distinct Azure regions. `CORTEX_ENABLED_CROSS_REGION = ANY_REGION` is already set, but cross-region inference is documented as not-supported for Cortex Analyst (it applies only to LLM functions like `COMPLETE`, `SUMMARIZE`, etc.).

The constraint is hard — no amount of config or grants makes this work in the current region.

## Options considered

1. **Move the Snowflake account to Azure East US 2.** Unblocks the full AI demo. Cost: rebuild storage integration (new tenant consent), rerun every Terraform apply from zero, reload ~1.8M rows via Snowpipe, rerun dbt, re-register GitHub secrets with the new account URL. Estimated 2-4 hours of rework, plus another Azure AD admin-consent cycle for a new Snowflake enterprise app. Puts in-flight work (CI, auto-ingest, MARTS) at risk of regression.

2. **Pivot to Cortex Search.** Text-search-over-documents. Works in more regions, possibly including `AZURE_EASTUS`. Different scope from NL-to-SQL — scope is document retrieval, not structured-data analytics. Weaker fit for the BI story; no overlap with the semantic model already built.

3. **Scale back to a Streamlit app without Cortex Analyst.** Keep every piece of Cortex-ready scaffolding (semantic model YAML, Terraform grants, the enablement flag) in place, but replace the Cortex Analyst REST call with a hand-written-SQL UI and pre-built per-domain queries. Document the deferred AI layer and the conditions under which it would light up.

## Decision

Chose **Option 3: scale back, preserve the scaffolding, ship working Streamlit today.**

Rationale:

- **Preserves investment.** The semantic model YAML, RBAC grants, stage, Streamlit resource, and `ENABLE_CORTEX_ANALYST` account setting all remain. If the account ever moves to East US 2 (or Cortex Analyst reaches East US), re-enabling is ~15 minutes: flip the Streamlit code to use `_snowflake.send_snow_api_request`, re-upload, done.
- **Ships a working app.** A Streamlit app with pre-built domain tabs (Finance, Portfolio, Risk) and a SQL playground still demonstrates Snowflake-native Streamlit deployment, correct use of session + warehouse + RBAC, and provides real analytical utility.
- **Honest portfolio narrative.** The portfolio writeup gains a section on region-availability trade-offs, cross-region inference limits, and when to pick Snowflake's own AI services vs alternatives. That's a more signal-rich story than pretending it works.
- **Low reversibility cost.** Re-enabling Cortex Analyst from here is trivial. The cost of moving the account is far higher than the cost of not having AI in the app today.

## Consequences

- **Semantic model (`streamlit/semantic_model/fsp_marts.yaml`) stays as-is.** It's still a valid portfolio artefact: it shows how to describe tables, dimensions, measures, synonyms, and verified queries for Cortex. Cost of keeping it: zero.
- **`snowflake_streamlit_analyst` Terraform module stays as-is.** Still creates the SEMANTIC schema, stage, Streamlit, and grants. Cortex Analyst enablement stays on.
- **`CORTEX_USER` grants to `FR_ENGINEER`, `FR_ANALYST`, and `ACCOUNTADMIN` stay.** Harmless when Cortex Analyst isn't live; ready when it is.
- **Streamlit app (`streamlit/app/streamlit_app.py`) is rewritten.** Drops the Cortex REST call. Replaced with:
  - Three domain tabs (Finance, Portfolio, Risk) with pre-built parametrised queries
  - A SQL playground tab for free-form queries (scoped to `ANALYTICS_DEV.MARTS`)
  - A prominent header note explaining the Cortex Analyst deferral with a link to this ADR
- **Diagnostic grant cleanup.** During debugging, `AR_ANALYTICS_DEV_MARTS_RO` was granted to `ACCOUNTADMIN` to test whether Cortex's auth check used direct grants. That grant is reverted (it was not codified in Terraform).

## Revisit triggers

Re-enable Cortex Analyst when any of these becomes true:

- Snowflake announces Cortex Analyst availability in `AZURE_EASTUS`.
- Snowflake enables Cortex Analyst cross-region inference.
- The project moves its Snowflake account to `AZURE_EASTUS2` or another supported region (only justified if there is another forcing function).

The change at that point is minimal: swap the query path in `streamlit_app.py` back to `_snowflake.send_snow_api_request("/api/v2/cortex/analyst/message", ...)` (a prior version is in git history), re-upload via `scripts/upload_streamlit_app.py`, done.
