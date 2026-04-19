{#
    Assets under management (AUM) aggregated monthly by fund.

    Grain: one row per (company, fund_sk, year_month).
    Supports AUM trends, fund concentration analysis, net flow calculations.

    Methodology: at each month-end, sum the latest valuation per
    (policy, fund) pair within that month. This approximates month-end
    book value.

    Measures:
      - aum_amount: sum of market_value_amount at month-end per fund
      - unique_policies, unique_clients: counts
      - aum_mom_change: MoM delta
      - aum_12m_avg: 12-month trailing average
#}

with monthly_valuations as (

    -- Latest valuation per (policy, fund) within each month
    select
        v.company
        , v.fund_sk
        , v.policy_sk
        , v.client_sk
        , d.year
        , d.month
        , d.month_start                         as year_month
        , v.market_value_amount
        , v.units
    from {{ ref('fct_valuations') }} v
    inner join {{ ref('dim_date') }} d on v.date_sk = d.date_sk
    where v.fund_sk is not null
      and v.market_value_amount is not null
    qualify row_number() over (
        partition by v.company, v.policy_sk, v.fund_sk, d.year, d.month
        order by v.valuation_date desc
    ) = 1

)

, aggregated as (

    select
        mv.company
        , mv.fund_sk
        , mv.year_month
        , mv.year
        , mv.month
        , sum(mv.market_value_amount)         as aum_amount
        , sum(mv.units)                       as total_units
        , count(distinct mv.policy_sk)        as unique_policies
        , count(distinct mv.client_sk)        as unique_clients
    from monthly_valuations mv
    group by 1, 2, 3, 4, 5

)

, enriched as (

    select
        a.*
        , f.fund_name
        , f.fund_type
        , f.jse_code

        , lag(a.aum_amount) over (
            partition by a.company, a.fund_sk
            order by a.year_month
          ) as aum_prior_month

        , avg(a.aum_amount) over (
            partition by a.company, a.fund_sk
            order by a.year_month
            rows between 11 preceding and current row
          ) as aum_12m_avg

    from aggregated a
    left join {{ ref('dim_fund') }} f on a.fund_sk = f.fund_sk

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'fund_sk', 'year_month']) }} as mart_key
        , company
        , fund_sk
        , fund_name
        , fund_type
        , jse_code
        , year_month
        , year
        , month
        , aum_amount
        , total_units
        , unique_policies
        , unique_clients
        , aum_prior_month
        , aum_amount - aum_prior_month              as aum_mom_change
        , case
            when aum_prior_month is not null and aum_prior_month <> 0
              then (aum_amount - aum_prior_month) / aum_prior_month
          end                                        as aum_mom_pct_change
        , aum_12m_avg
        , current_timestamp() as _loaded_at
    from enriched

)

select * from final
