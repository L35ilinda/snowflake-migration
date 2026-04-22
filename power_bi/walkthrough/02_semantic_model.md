# 02 — Build the semantic model

Tables, relationships, measures, hierarchies. DirectQuery throughout —
nothing imported. The semantic layer lives in the .pbix; the physical
tables and their grain are what dbt shipped in CORE/MARTS.

## Load tables

In the Navigator (from step 01), tick these boxes and click **Load**:

**MARTS (facts):**
- `finance_advisor_commissions_monthly`
- `portfolio_aum_monthly`
- `risk_policy_inforce`

**CORE (dimensions):**
- `dim_advisor`
- `dim_date`
- `dim_client`
- `dim_fund`
- `dim_policy`
- `dim_product`

**NOT** `dim_policy_history` — that's the Type 2 history view for
point-in-time queries; the semantic model uses current state
(`dim_policy`) for standard BI.

## Rename queries for readability

In the Data pane (right side), rename the loaded queries to drop the
Snowflake-style lowercase prefix:
- `finance_advisor_commissions_monthly` → `Fact Commissions Monthly`
- `portfolio_aum_monthly` → `Fact AUM Monthly`
- `risk_policy_inforce` → `Fact Policies In-Force`
- `dim_advisor` → `Advisor`
- `dim_date` → `Date`
- `dim_client` → `Client`
- `dim_fund` → `Fund`
- `dim_policy` → `Policy`
- `dim_product` → `Product`

Model-visible names are analyst-facing — lowercase-snake from Snowflake
is an implementation detail.

## Mark the date dimension

Model view (left ribbon, three-tables icon) → right-click `Date` →
**Mark as date table** → choose the `date` column. Required for
time-intelligence DAX (`DATEADD`, `SAMEPERIODLASTYEAR`, etc.).

## Define relationships

Power BI tries to auto-detect. Verify / fix in Model view:

| From (fact) | Column | To (dim) | Column | Cardinality |
|---|---|---|---|---|
| Fact Commissions Monthly | `advisor_sk` | Advisor | `advisor_sk` | Many-to-one |
| Fact Commissions Monthly | `date_sk` | Date | `date_sk` | Many-to-one |
| Fact AUM Monthly | `client_sk` | Client | `client_sk` | Many-to-one |
| Fact AUM Monthly | `fund_sk` | Fund | `fund_sk` | Many-to-one |
| Fact AUM Monthly | `date_sk` | Date | `date_sk` | Many-to-one |
| Fact Policies In-Force | `policy_sk` | Policy | `policy_sk` | Many-to-one |
| Fact Policies In-Force | `advisor_sk` | Advisor | `advisor_sk` | Many-to-one |

**All relationships single-direction** (filter flows dim → fact).
Avoid bidirectional unless a specific cross-filter is required;
bidirectional on DirectQuery is a footgun.

Inactive relationships: none needed for v0.3.0.

## Build a date hierarchy

Data pane → right-click `Date` table → **New hierarchy** → name it
`Calendar`. Drag `date_year` → `date_quarter_name` → `date_month_name`
into the hierarchy in that order.

## Measures

Create these as **explicit DAX measures** (right-click the fact table →
**New measure**). Format each appropriately.

```dax
-- Fact Commissions Monthly ---
Total Net Commission =
    SUM('Fact Commissions Monthly'[net_commission_amount])

Avg Commission per Advisor =
    DIVIDE(
        [Total Net Commission],
        DISTINCTCOUNT(Advisor[advisor_sk])
    )

MoM Commission Delta =
    VAR current_month = [Total Net Commission]
    VAR prior_month =
        CALCULATE(
            [Total Net Commission],
            DATEADD('Date'[date], -1, MONTH)
        )
    RETURN current_month - prior_month

MoM Commission Pct =
    DIVIDE(
        [MoM Commission Delta],
        CALCULATE([Total Net Commission], DATEADD('Date'[date], -1, MONTH))
    )

-- Fact AUM Monthly ---
Total AUM =
    SUM('Fact AUM Monthly'[market_value_amount])

Distinct Clients =
    DISTINCTCOUNT('Fact AUM Monthly'[client_sk])

Avg AUM per Client =
    DIVIDE([Total AUM], [Distinct Clients])

-- Fact Policies In-Force ---
Active Policies =
    CALCULATE(
        DISTINCTCOUNT('Fact Policies In-Force'[policy_sk]),
        'Fact Policies In-Force'[is_inforce] = TRUE
    )

Total Sum Assured (In-Force) =
    CALCULATE(
        SUM('Fact Policies In-Force'[total_sum_assured]),
        'Fact Policies In-Force'[is_inforce] = TRUE
    )
```

**Column names above must match the actual mart columns.** If a name
differs, fix the DAX — don't rename the column on the Power BI side
(project rule: derive in dbt, not Power BI).

## Build one dashboard page per domain

Create three report pages:

1. **Finance — Advisor Commissions**
   - Card: `Total Net Commission`, `Avg Commission per Advisor`, `MoM Commission Pct`
   - Line chart: `Total Net Commission` by `Date[Calendar]` (month)
   - Matrix: `Advisor[advisor_name]` rows × `Date[date_year]` columns, `Total Net Commission` values
   - Slicer: `Date[date_year]`

2. **Portfolio — AUM**
   - Card: `Total AUM`, `Distinct Clients`, `Avg AUM per Client`
   - Area chart: `Total AUM` by `Date[Calendar]`
   - Bar chart: top 20 `Fund[fund_name]` by `Total AUM`

3. **Risk — Policies In-Force**
   - Card: `Active Policies`, `Total Sum Assured (In-Force)`
   - Pie chart: `Policy[product_type]` share of `Active Policies`
   - Matrix: `Advisor[advisor_name]` × `Policy[policy_status]`, `Active Policies` values

## Verify

- Every visual renders within ~3-5s (DirectQuery; first render per page
  hits `BI_WH`).
- Relationships light up the cross-filter — click a year on the line
  chart, the matrix filters.
- `MoM Commission Delta` evaluates to sensible values (not blank) —
  confirms the date dimension is marked correctly.

## Save

**File → Save As → `power_bi/fsp_marts.pbix`** (repo root path).

## Screenshots to capture

- `screenshots/01_model_view.png` — Model view with all relationships
  visible.
- `screenshots/02_finance_page.png` — Finance page with live data.
- `screenshots/03_portfolio_page.png` — Portfolio page.
- `screenshots/04_risk_page.png` — Risk page.

## Next

[03 — Build the paginated report](03_paginated_report.md).
