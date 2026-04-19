{#
    Investment portfolio valuations fact.

    Grain: one row per (company, policy_number, fund_name, valuation_date).
    Sources: valuations staging from all three tenants.

    FKs:
      - advisor_sk  → dim_advisor on (company, advisor_identifier)
      - product_sk  → dim_product on (company, 'INVESTMENT', coalesce(product_code, product_name))
      - fund_sk     → dim_fund on (company, fund_name)
      - date_sk     → dim_date on valuation_date

    Source rows have ~15% nulls in advisor_identifier, product_code,
    product_name, fund_code, and fund_name. We LEFT JOIN to dims so nulls
    propagate; relationship tests use severity=warn for the FKs.
#}

with valuations_union as (

    select
        'MAIN_BOOK' as company
        , advisor_identifier
        , client_id_number
        , policy_number
        , product_code
        , product_name
        , fund_code
        , fund_name
        , jse_code
        , valuation_date
        , currency
        , market_value_amount
        , units
        , anniversary_month
        , monthly_income_amount
        , monthly_income_pct
        , income_frequency
        , _loaded_at
    from {{ ref('stg_main_book__valuations') }}

    union all select
        'INDIGO_INSURANCE', advisor_identifier, client_id_number, policy_number,
        product_code, product_name, fund_code, fund_name, jse_code, valuation_date,
        currency, market_value_amount, units, anniversary_month, monthly_income_amount,
        monthly_income_pct, income_frequency, _loaded_at
    from {{ ref('stg_indigo_insurance__valuations') }}

    union all select
        'HORIZON_ASSURANCE', advisor_identifier, client_id_number, policy_number,
        product_code, product_name, fund_code, fund_name, jse_code, valuation_date,
        currency, market_value_amount, units, anniversary_month, monthly_income_amount,
        monthly_income_pct, income_frequency, _loaded_at
    from {{ ref('stg_horizon_assurance__valuations') }}

)

, disambiguated as (

    -- Source data has ~8% rows with null policy_number or valuation_date,
    -- which would collide on the natural grain. Add a row-within-grain
    -- sequence so every row is uniquely addressable, and flag whether the
    -- natural grain is complete for downstream filtering.
    select
        *
        , row_number() over (
            partition by company, coalesce(policy_number, '_NULL_'),
                         coalesce(fund_name, '_NULL_'),
                         coalesce(valuation_date, '1900-01-01'::date)
            order by market_value_amount, units, _loaded_at
          ) as _row_in_grain
        , case
            when policy_number is not null and valuation_date is not null
              then true
            else false
          end as has_complete_grain
    from valuations_union

)

, with_sks as (

    select
        -- Grain surrogate key (includes disambiguator for data-quality reasons)
        {{ dbt_utils.generate_surrogate_key([
            'company', 'policy_number', 'fund_name', 'valuation_date',
            '_row_in_grain'
        ]) }} as valuation_sk

        -- FKs (null-safe: nulls in natural keys produce null SKs that will not
        -- match any dim row, so LEFT JOIN below leaves them null)
        , case when advisor_identifier is not null
            then {{ dbt_utils.generate_surrogate_key(['company', 'advisor_identifier']) }}
          end as advisor_sk

        , case when coalesce(product_code, product_name) is not null
            then {{ dbt_utils.generate_surrogate_key([
                "company", "'INVESTMENT'", "coalesce(product_code, product_name)"
            ]) }}
          end as product_sk

        , case when fund_name is not null
            then {{ dbt_utils.generate_surrogate_key(['company', 'fund_name']) }}
          end as fund_sk

        , case when valuation_date is not null
            then to_char(valuation_date, 'YYYYMMDD')::int
          end as date_sk

        , case when policy_number is not null
            then {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }}
          end as policy_sk

        , case when client_id_number is not null
            then {{ dbt_utils.generate_surrogate_key(['company', 'client_id_number']) }}
          end as client_sk

        -- Degenerate and descriptive columns
        , company
        , policy_number
        , client_id_number
        , valuation_date
        , currency
        , anniversary_month
        , income_frequency
        , has_complete_grain

        -- Measures
        , market_value_amount
        , units
        , monthly_income_amount
        , monthly_income_pct

        , _loaded_at
    from disambiguated

)

select * from with_sks
