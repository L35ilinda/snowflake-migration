# 01 — Connect Power BI Desktop to Snowflake (build phase)

OAuth as `LSILINDA` is the right auth for the build phase — no service-user
credential roundtrip while you're iterating. Switch to `PBI_SVC` key-pair
only at publish time (`04_publish.md`).

## Prerequisites

- Power BI Desktop installed (free, Microsoft Store or
  https://aka.ms/pbiSingleInstaller).
- A Snowflake browser session — Power BI's Snowflake connector pops a
  browser tab for SSO; you'll authorize there with `LSILINDA`.

## Steps

1. **Open Power BI Desktop.** Close the splash. **Home → Get data → More**.
2. Search **Snowflake** → select **Snowflake** → **Connect**.
3. Connection details:
   - **Server:** `vncenfn-xf07416.snowflakecomputing.com`
     (org-account identifier from CLAUDE.md §3 → `<org>-<account>.snowflakecomputing.com`)
   - **Warehouse:** `BI_WH`
   - **Data Connectivity mode:** **DirectQuery** (per ADR-0017 §2)
   - **Advanced options:**
     - **Role:** `FR_ANALYST`
     - **Database:** `ANALYTICS_DEV`
     - Leave the rest blank.
4. Click **OK**. Auth dialog appears.
5. **Authentication:** **Microsoft account** → **Sign in**.
   - Browser opens → log in with the Snowflake user you've configured for
     SSO (typically the `LSILINDA` Microsoft Entra identity if SSO is set
     up; otherwise use **Snowflake authentication** with username
     `LSILINDA` + your Snowflake password). Either works for the build
     phase.
   - Tick **Apply this setting to: vncenfn-xf07416.snowflakecomputing.com**
     so subsequent reconnects don't re-prompt.
6. **Connect**. The Navigator appears. You should see databases —
   expand `ANALYTICS_DEV` and confirm `MARTS`, `CORE`, `STAGING` are
   listed.

## Verify

- In the Navigator, expand `ANALYTICS_DEV` → `MARTS` → click
  `finance_advisor_commissions_monthly`. Preview pane on the right
  should show ~rows of data within ~3-5 seconds (DirectQuery hits
  `BI_WH`; first hit pays the warehouse-resume cost).
- If the preview times out: warehouse may already be auto-suspended
  twice and Snowsight may be queued — wait 30s and click again.

## Common failures

- **"Failed to authenticate" / browser loop with no result.** Cached
  Microsoft credentials are stale. Power BI Desktop → File → Options
  and settings → Data source settings → find the Snowflake source →
  Edit Permissions → Clear All Permissions → reconnect.
- **"Object does not exist or operation cannot be performed"** when
  expanding a schema. `FR_ANALYST` doesn't have RO on `RAW_*` schemas
  (intentional, per ADR-0006 / project pattern). Expected — only
  `STAGING`, `CORE`, `MARTS`, `RAW_QUARANTINE`, `SEMANTIC` should be
  visible.
- **Connector says "import only"**, no DirectQuery option. You're on
  an older Power BI Desktop. Update — DirectQuery for Snowflake has
  been GA since at least 2020.

## Next

[02 — Build the semantic model](02_semantic_model.md).
