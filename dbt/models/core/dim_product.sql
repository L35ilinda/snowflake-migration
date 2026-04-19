{#
    Conformed product dimension.

    Products come from two distinct universes:
      - Investment products: valuations tables have (product_code, product_name).
        Examples: LA (Living Annuity), RA (Retirement Annuity).
      - Insurance products: insurance/assurance tables have product_name only,
        no code. Examples: Indigo Premier, Horizon LifeLine.

    Natural key per tenant = COALESCE(product_code, product_name).
    product_category distinguishes INVESTMENT vs INSURANCE.

    Valuations rows with both nulls are filtered out (noise).
    product_code is optional (null for insurance products).
#}

with valuations_products as (

    select distinct
        'MAIN_BOOK' as company
        , 'INVESTMENT' as product_category
        , product_code
        , product_name
    from {{ ref('stg_main_book__valuations') }}
    where product_code is not null or product_name is not null

    union all select distinct 'INDIGO_INSURANCE', 'INVESTMENT', product_code, product_name
    from {{ ref('stg_indigo_insurance__valuations') }}
    where product_code is not null or product_name is not null

    union all select distinct 'HORIZON_ASSURANCE', 'INVESTMENT', product_code, product_name
    from {{ ref('stg_horizon_assurance__valuations') }}
    where product_code is not null or product_name is not null

)

, insurance_products as (

    -- Main Book risk_benefits has no product_name column; skip it.
    select distinct
        'INDIGO_INSURANCE' as company
        , 'INSURANCE' as product_category
        , cast(null as varchar) as product_code
        , product_name
    from {{ ref('stg_indigo_insurance__insurance') }}
    where product_name is not null

    union all select distinct 'HORIZON_ASSURANCE', 'INSURANCE', cast(null as varchar), product_name
    from {{ ref('stg_horizon_assurance__assurance') }}
    where product_name is not null

)

, all_products as (

    select * from valuations_products
    union all
    select * from insurance_products

)

, deduped as (

    -- Collapse rows that differ only in a null. For a given (company, category,
    -- code), pick the non-null name if any exists. Same for code given name.
    select
        company
        , product_category
        , coalesce(product_code, product_name) as natural_key
        , max(product_code) as product_code
        , max(product_name) as product_name
    from all_products
    group by company, product_category, coalesce(product_code, product_name)

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'product_category', 'natural_key']) }} as product_sk
        , company
        , product_category
        , product_code
        , product_name
        , current_timestamp() as _loaded_at
    from deduped

)

select * from final
