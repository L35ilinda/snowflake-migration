-- CI smoke test: trivial change to trigger dbt_ci.yml end-to-end.
with source as (

    select * from {{ source('raw_main_book', 'main_book_valuations') }}

)

, renamed as (

    select
        advisor_identifier
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , client_id_number
        , policy_number
        , product_name
        , product_code
        , fund_name
        , fund_code
        , jse_code
        , valuation_date::date                  as valuation_date
        , currency
        , market_value_amount::number(18, 2)    as market_value_amount
        , units::number(18, 4)                  as units
        , anniversary_month::int                as anniversary_month
        , monthly_income_amount::number(18, 2)  as monthly_income_amount
        , monthly_income_pct::number(8, 4)      as monthly_income_pct
        , income_frequency
        , _loaded_at
    from source

)

select * from renamed
