# 03 — Paginated report (SSRS replacement)

One Power BI Paginated Report — a monthly advisor commission statement,
parameterized by `advisor_identifier` and `month`. Built in **Power BI
Report Builder** (separate tool from Power BI Desktop). This is the
direct SSRS replacement story — same .rdl format, same parameterization
model, same fixed-layout rendering paradigm.

## Prerequisites

- **Power BI Report Builder** installed (free, separate download from
  https://aka.ms/pbireportbuilder).
- The .pbix from step 02 saved (you'll re-use the connection details).

## Why Import (not DirectQuery) for this report

Per ADR-0017 §2: a paginated report renders once per parameterized run.
Import means the dataset query runs at render time against `BI_WH`,
materializes its result set, and renders once. There's no interactive
re-querying — DirectQuery's value (sub-second cross-filter pushdown)
doesn't apply.

## Steps

### Create dataset connection

1. Open Power BI Report Builder.
2. Right-click **Data Sources** → **Add Data Source**.
3. Name: `SnowflakeMarts`. **Use a connection embedded in my report**.
4. **Type:** ODBC.
5. **Connection string** (replace the password placeholder):
   ```
   Driver={SnowflakeDSIIDriver};Server=vncenfn-xf07416.snowflakecomputing.com;Database=ANALYTICS_DEV;Warehouse=BI_WH;Role=FR_ANALYST;Schema=MARTS;Uid=LSILINDA;Pwd=<your password>
   ```
   - For build phase use `LSILINDA` + Snowflake password.
   - At publish (step 04) the connection switches to `PBI_SVC` +
     key-pair via the Power BI Service gateway/cloud connection.
6. Test → OK.

> **Snowflake ODBC driver** must be installed locally
> (https://docs.snowflake.com/en/developer-guide/odbc/odbc-windows).

### Define dataset

Right-click **Datasets** → **Add Dataset**. Name: `dsCommissions`.
Use the `SnowflakeMarts` data source. Query type: **Text**. Query:

```sql
select
      f.advisor_identifier
    , a.advisor_name
    , f.commission_month
    , f.business_line
    , f.gross_commission_amount
    , f.vat_amount
    , f.net_commission_amount
    , f.commission_count
from analytics_dev.marts.finance_advisor_commissions_monthly f
join analytics_dev.core.dim_advisor a
  on a.advisor_sk = f.advisor_sk
where f.advisor_identifier = @advisor_identifier
  and f.commission_month = to_date(@month_start)
order by f.business_line, f.gross_commission_amount desc
;
```

### Define parameters

Right-click **Parameters** → **Add Parameter**:

1. **Name:** `advisor_identifier`. **Prompt:** `Advisor`. **Data type:**
   Text. **Default values:** none. Available values: from a query
   `select distinct advisor_identifier from analytics_dev.core.dim_advisor order by 1`.
2. **Name:** `month_start`. **Prompt:** `Month start (YYYY-MM-01)`.
   **Data type:** Date/Time. **Default values:** specify
   `=DateSerial(Year(Today()), Month(Today())-1, 1)` (last full month).

### Lay out the report

Pre-built template wins over hand-laid for time. **Insert → Table** →
drag from the field list:

| Column | Field |
|---|---|
| Business Line | `business_line` |
| Gross | `gross_commission_amount` (currency, ZAR R0.00) |
| VAT | `vat_amount` (currency) |
| Net | `net_commission_amount` (currency, bold) |
| Count | `commission_count` |

Add:
- **Header:** "Monthly Commission Statement" + parameter values
  (`=Parameters!advisor_identifier.Value`, `=Format(Parameters!month_start.Value, "MMMM yyyy")`).
- **Footer:** advisor full name (`=First(Fields!advisor_name.Value, "dsCommissions")`),
  page number, generated-at timestamp.
- **Group footer (per advisor):** `Sum(net_commission_amount)` row.

### Render

**Run** (top-left, ! icon). Parameters dialog appears. Pick an advisor
and month. Renders as a fixed-layout multi-page report (PDF-ready).

### Save

**File → Save As → `power_bi/fsp_advisor_commissions.rdl`** in the repo.

The `.rdl` is XML — **commit it as text**, it diffs well across
revisions.

## Screenshots to capture

- `screenshots/05_paginated_design.png` — Report Builder design
  surface with the table and parameters visible.
- `screenshots/06_paginated_rendered.png` — A rendered statement
  for one advisor / month.

## Common failures

- **"ODBC Driver not found"** — Snowflake ODBC driver not installed.
  Install it and reopen Report Builder.
- **"Object does not exist"** at query design time — `MARTS` schema
  qualifier missing somewhere; fully qualify
  (`analytics_dev.marts.finance_advisor_commissions_monthly`).
- **Empty result with valid parameters** — `commission_month` is a
  date type in the mart; ensure the parameter cast (`to_date(@month_start)`)
  matches and that you're picking a month that actually has data
  (`select distinct commission_month from analytics_dev.marts.finance_advisor_commissions_monthly`).

## Next

[04 — Publish with PBI_SVC service identity](04_publish.md).
