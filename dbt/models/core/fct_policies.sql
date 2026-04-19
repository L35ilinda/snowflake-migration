{#
    Policy-level accumulating snapshot fact.

    Grain: one row per (company, policy_number). Since source data is a
    single snapshot with no history, this is effectively an accumulating
    snapshot at snapshot_date = dbt run date.

    Joins dim_policy to aggregated measures from fct_commissions,
    fct_valuations, and fct_transactions to produce a one-stop portfolio
    view per policy.

    FKs:
      - policy_sk    → dim_policy (1:1, PK here)
      - advisor_sk   → dim_advisor (via risk-policy attributes) — null for INVESTMENT
      - date_sk      → dim_date on snapshot_date

    Measures (lifetime, additive within the policy):
      - commission_count, commission_gross_total, commission_net_total
      - transaction_count, transaction_amount_total
      - valuation_count, latest_market_value, avg_market_value
      - For RISK policies: total_monthly_premium, all benefit amounts from dim
      - For INVESTMENT policies: latest_market_value from valuations

    If a downstream need arises for true periodic snapshots, write
    historical rows to a new `fct_policy_snapshots` table with snapshot_date
    as part of grain.
#}

with policies as (

    select * from {{ ref('dim_policy') }}

)

, commission_rollup as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_sk
        , count(*)                               as commission_count
        , sum(gross_amount)                      as commission_gross_total
        , sum(net_amount)                        as commission_net_total
        , max(transaction_date)                  as last_commission_date
    from {{ ref('fct_commissions') }}
    where policy_number is not null
    group by company, policy_number

)

, valuation_rollup as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_sk
        , count(*)                               as valuation_count
        , avg(market_value_amount)               as avg_market_value
        , max(valuation_date)                    as last_valuation_date
    from {{ ref('fct_valuations') }}
    where policy_number is not null
    group by company, policy_number

)

, latest_valuation as (

    -- Grab the market value from the most recent valuation per policy.
    select
        {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_sk
        , market_value_amount as latest_market_value
    from {{ ref('fct_valuations') }}
    where policy_number is not null
    qualify row_number() over (
        partition by company, policy_number
        order by valuation_date desc nulls last, _loaded_at desc nulls last
    ) = 1

)

, transaction_rollup as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_sk
        , count(*)                               as transaction_count
        , sum(amount)                            as transaction_amount_total
        , max(transaction_date)                  as last_transaction_date
    from {{ ref('fct_transactions') }}
    where policy_number is not null
    group by company, policy_number

)

, snapshot_date_cte as (
    select
        current_date()                           as snapshot_date
        , to_char(current_date(), 'YYYYMMDD')::int as snapshot_date_sk
)

, final as (

    select
        p.policy_sk
        , s.snapshot_date_sk                      as date_sk
        , s.snapshot_date

        -- Advisor FK (null for investment policies that don't carry advisor)
        , case when p.company is not null and p.policy_universe = 'RISK' then null end as advisor_sk

        -- Descriptors from dim_policy
        , p.company
        , p.policy_number
        , p.policy_universe
        , p.policy_status
        , p.inception_date
        , case
            when p.inception_date is not null
              then datediff('year', p.inception_date, current_date())
          end                                     as policy_age_years
        , p.product_name

        -- Risk policy measures
        , p.total_monthly_premium
        , p.life_sum_assured
        , p.life_premium
        , p.disability_sum_assured
        , p.disability_premium
        , p.chronic_premium
        , p.accident_premium

        -- Roll-ups
        , coalesce(cr.commission_count, 0)        as commission_count
        , cr.commission_gross_total
        , cr.commission_net_total
        , cr.last_commission_date

        , coalesce(vr.valuation_count, 0)         as valuation_count
        , vr.avg_market_value
        , lv.latest_market_value
        , vr.last_valuation_date

        , coalesce(tr.transaction_count, 0)       as transaction_count
        , tr.transaction_amount_total
        , tr.last_transaction_date

        , current_timestamp()                     as _loaded_at
    from policies p
    cross join snapshot_date_cte s
    left join commission_rollup cr   on p.policy_sk = cr.policy_sk
    left join valuation_rollup vr    on p.policy_sk = vr.policy_sk
    left join latest_valuation lv    on p.policy_sk = lv.policy_sk
    left join transaction_rollup tr  on p.policy_sk = tr.policy_sk

)

select * from final
