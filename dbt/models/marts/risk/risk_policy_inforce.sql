{#
    Risk policy book snapshot by status.

    Grain: one row per (company, policy_status, smoker_status, income_bracket).
    Drives book-in-force dashboards and premium income summaries.

    Only RISK policies — INVESTMENT policies are out of scope here
    (they have no premium/status concept).

    Measures:
      - policy_count
      - active_policy_count (where policy_status = 'Active')
      - total_monthly_premium_sum (monthly book income)
      - avg_monthly_premium
      - avg_age
      - avg_sum_assured
#}

with risk_policies as (

    select
        p.policy_sk
        , p.company
        , p.policy_number
        , p.policy_status
        , p.smoker_status
        , p.income_bracket
        , p.age_next
        , p.total_monthly_premium
        , p.life_sum_assured
        , p.disability_sum_assured
        , p.inception_date
    from {{ ref('dim_policy') }} p
    where p.policy_universe = 'RISK'

)

, aggregated as (

    select
        company
        , coalesce(policy_status, 'UNKNOWN')      as policy_status
        , coalesce(smoker_status, 'UNKNOWN')      as smoker_status
        , coalesce(income_bracket, 'UNKNOWN')     as income_bracket

        , count(*)                                as policy_count
        , count_if(policy_status = 'Active')      as active_policy_count
        , count_if(policy_status = 'Lapsed')      as lapsed_policy_count
        , count_if(policy_status = 'Cancelled')   as cancelled_policy_count
        , count_if(policy_status = 'Pending')     as pending_policy_count

        , sum(total_monthly_premium)              as total_monthly_premium_sum
        , avg(total_monthly_premium)              as avg_monthly_premium
        , sum(total_monthly_premium) * 12         as annualised_premium

        , avg(age_next)                           as avg_age_next
        , sum(life_sum_assured)                   as total_life_sum_assured
        , avg(life_sum_assured)                   as avg_life_sum_assured
        , sum(disability_sum_assured)             as total_disability_sum_assured
    from risk_policies
    group by 1, 2, 3, 4

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'company', 'policy_status', 'smoker_status', 'income_bracket'
        ]) }} as mart_key
        , company
        , policy_status
        , smoker_status
        , income_bracket
        , policy_count
        , active_policy_count
        , lapsed_policy_count
        , cancelled_policy_count
        , pending_policy_count
        , active_policy_count / nullif(policy_count, 0)::float   as active_rate
        , lapsed_policy_count / nullif(policy_count, 0)::float   as lapse_rate
        , total_monthly_premium_sum
        , avg_monthly_premium
        , annualised_premium
        , avg_age_next
        , total_life_sum_assured
        , avg_life_sum_assured
        , total_disability_sum_assured
        , current_timestamp() as _loaded_at
    from aggregated

)

select * from final
