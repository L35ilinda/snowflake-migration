{#
    Advisor commission performance, aggregated monthly.

    Grain: one row per (company, advisor_sk, year_month, commission_category).
    Supports advisor scorecards, YoY comparison, category splits.

    Measures:
      - commission_count, commission_gross_total, commission_net_total,
        avg_commission_amount
      - running_net_total: cumulative net commission per advisor over time
      - net_total_prior_year: same month last year, same advisor
      - pct_change_yoy: (current - prior) / nullif(prior, 0)
#}

with commissions as (

    select
        c.commission_sk
        , c.advisor_sk
        , c.company
        , c.commission_category
        , c.gross_amount
        , c.net_amount
        , d.year
        , d.month
        , d.month_start as year_month
    from {{ ref('fct_commissions') }} c
    inner join {{ ref('dim_date') }} d on c.date_sk = d.date_sk
    where c.advisor_sk is not null

)

, aggregated as (

    select
        c.company
        , c.advisor_sk
        , c.year_month
        , c.year
        , c.month
        , c.commission_category
        , count(*)                        as commission_count
        , sum(c.gross_amount)             as commission_gross_total
        , sum(c.net_amount)               as commission_net_total
        , avg(c.net_amount)               as avg_commission_amount
    from commissions c
    group by 1, 2, 3, 4, 5, 6

)

, enriched as (

    select
        a.*
        , adv.advisor_identifier
        , sum(a.commission_net_total) over (
            partition by a.company, a.advisor_sk, a.commission_category
            order by a.year_month
            rows between unbounded preceding and current row
          ) as running_net_total

        , lag(a.commission_net_total) over (
            partition by a.company, a.advisor_sk, a.commission_category, a.month
            order by a.year
          ) as net_total_prior_year

    from aggregated a
    left join {{ ref('dim_advisor') }} adv on a.advisor_sk = adv.advisor_sk

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'company', 'advisor_sk', 'year_month', 'commission_category'
        ]) }} as mart_key
        , company
        , advisor_sk
        , advisor_identifier
        , year_month
        , year
        , month
        , commission_category
        , commission_count
        , commission_gross_total
        , commission_net_total
        , avg_commission_amount
        , running_net_total
        , net_total_prior_year
        , case
            when net_total_prior_year is not null and net_total_prior_year <> 0
              then (commission_net_total - net_total_prior_year) / net_total_prior_year
          end as pct_change_yoy
        , current_timestamp() as _loaded_at
    from enriched

)

select * from final
