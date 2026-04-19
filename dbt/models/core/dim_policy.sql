{#
    Conformed policy dimension.

    Two policy universes per tenant:
      - RISK:       master data in risk_benefits / insurance / assurance
                    tables. Prefix RB*/IND*/HZR*. Full attributes.
      - INVESTMENT: only referenced in valuations + transactions. No master
                    record. Prefix POL*/INV*/HZV*. Minimal attributes.

    Grain: one row per (company, policy_number).

    Type 1 today (latest state per policy). Type 2-ready columns included
    (`is_current`, `valid_from`, `valid_to`) so we can transition to dbt
    snapshots once we start receiving dated policy-master files. Today
    every row has is_current = TRUE, valid_from = _loaded_at,
    valid_to = '9999-12-31'.
#}

with risk_policies as (

    -- Main Book risk_benefits (no product_name column)
    select
        'MAIN_BOOK' as company
        , policy_number
        , 'RISK' as policy_universe
        , inception_date
        , policy_status
        , member_id
        , age_next
        , smoker_status
        , income_bracket
        , cast(null as varchar) as product_name
        , life_sum_assured
        , life_premium
        , disability_type
        , disability_sum_assured
        , disability_premium
        , chronic_level
        , chronic_waiting_period
        , chronic_premium
        , accident_benefit
        , accident_premium
        , total_monthly_premium
        , commission_rate
        , _loaded_at
    from {{ ref('stg_main_book__risk_benefits') }}
    where policy_number is not null

    -- Indigo insurance (has product_name)
    union all select
        'INDIGO_INSURANCE', policy_number, 'RISK', inception_date, policy_status,
        member_id, age_next, smoker_status, income_bracket, product_name,
        life_sum_assured, life_premium, disability_type, disability_sum_assured,
        disability_premium, chronic_level, chronic_waiting_period, chronic_premium,
        accident_benefit, accident_premium, total_monthly_premium, commission_rate,
        _loaded_at
    from {{ ref('stg_indigo_insurance__insurance') }}
    where policy_number is not null

    -- Horizon assurance (has product_name)
    union all select
        'HORIZON_ASSURANCE', policy_number, 'RISK', inception_date, policy_status,
        member_id, age_next, smoker_status, income_bracket, product_name,
        life_sum_assured, life_premium, disability_type, disability_sum_assured,
        disability_premium, chronic_level, chronic_waiting_period, chronic_premium,
        accident_benefit, accident_premium, total_monthly_premium, commission_rate,
        _loaded_at
    from {{ ref('stg_horizon_assurance__assurance') }}
    where policy_number is not null

)

, risk_deduped as (

    -- Risk tables can have multiple rows per policy (different snapshots
    -- or repeat uploads). Keep the most recently loaded row per policy.
    select *
    from risk_policies
    qualify row_number() over (
        partition by company, policy_number
        order by _loaded_at desc nulls last
    ) = 1

)

, investment_policy_numbers as (

    -- Distinct policy_numbers from valuations/transactions that are NOT
    -- already in the risk universe. These get minimal attributes.
    select distinct
        'MAIN_BOOK' as company
        , policy_number
    from {{ ref('stg_main_book__valuations') }}
    where policy_number is not null

    union select distinct 'MAIN_BOOK', policy_number
    from {{ ref('stg_main_book__valuation_transactions') }}
    where policy_number is not null

    union select distinct 'INDIGO_INSURANCE', policy_number
    from {{ ref('stg_indigo_insurance__valuations') }}
    where policy_number is not null

    union select distinct 'INDIGO_INSURANCE', policy_number
    from {{ ref('stg_indigo_insurance__transactions') }}
    where policy_number is not null

    union select distinct 'HORIZON_ASSURANCE', policy_number
    from {{ ref('stg_horizon_assurance__valuations') }}
    where policy_number is not null

    union select distinct 'HORIZON_ASSURANCE', policy_number
    from {{ ref('stg_horizon_assurance__transactions') }}
    where policy_number is not null

)

, investment_policies as (

    select
        ip.company
        , ip.policy_number
        , 'INVESTMENT' as policy_universe
        , cast(null as date)    as inception_date
        , cast(null as varchar) as policy_status
        , cast(null as varchar) as member_id
        , cast(null as int)     as age_next
        , cast(null as varchar) as smoker_status
        , cast(null as varchar) as income_bracket
        , cast(null as varchar) as product_name
        , cast(null as number(18, 2)) as life_sum_assured
        , cast(null as number(18, 2)) as life_premium
        , cast(null as varchar) as disability_type
        , cast(null as number(18, 2)) as disability_sum_assured
        , cast(null as number(18, 2)) as disability_premium
        , cast(null as varchar) as chronic_level
        , cast(null as varchar) as chronic_waiting_period
        , cast(null as number(18, 2)) as chronic_premium
        , cast(null as number(18, 2)) as accident_benefit
        , cast(null as number(18, 2)) as accident_premium
        , cast(null as number(18, 2)) as total_monthly_premium
        , cast(null as number(8, 4))  as commission_rate
        , current_timestamp() as _loaded_at
    from investment_policy_numbers ip
    left join risk_deduped r
      on ip.company = r.company and ip.policy_number = r.policy_number
    where r.policy_number is null

)

, unioned as (

    select * from risk_deduped
    union all
    select * from investment_policies

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_sk
        , company
        , policy_number
        , policy_universe
        , inception_date
        , policy_status
        , member_id
        , age_next
        , smoker_status
        , income_bracket
        , product_name
        , life_sum_assured
        , life_premium
        , disability_type
        , disability_sum_assured
        , disability_premium
        , chronic_level
        , chronic_waiting_period
        , chronic_premium
        , accident_benefit
        , accident_premium
        , total_monthly_premium
        , commission_rate

        -- Type 2-ready columns (defaults suit Type 1; flip logic when we
        -- start receiving dated snapshots).
        , true                           as is_current
        , coalesce(_loaded_at, current_timestamp()) as valid_from
        , '9999-12-31 00:00:00'::timestamp_ntz as valid_to

        , _loaded_at
    from unioned

)

select * from final
