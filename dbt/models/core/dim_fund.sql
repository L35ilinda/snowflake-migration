{#
    Conformed fund dimension.

    Funds only appear in valuations tables. fund_code, fund_name, and jse_code
    are each independently nullable, so we use fund_name as the natural key
    (most populated in sampling) and coalesce the other attributes using MAX
    to grab a non-null value per group.

    jse_code is only populated for JSE-listed ETFs. Most regular unit trusts
    have fund_code + fund_name but no jse_code.
#}

with funds_raw as (

    select
        'MAIN_BOOK' as company
        , fund_code
        , fund_name
        , jse_code
    from {{ ref('stg_main_book__valuations') }}
    where fund_name is not null

    union all select 'INDIGO_INSURANCE', fund_code, fund_name, jse_code
    from {{ ref('stg_indigo_insurance__valuations') }}
    where fund_name is not null

    union all select 'HORIZON_ASSURANCE', fund_code, fund_name, jse_code
    from {{ ref('stg_horizon_assurance__valuations') }}
    where fund_name is not null

)

, deduped as (

    -- Collapse by (company, fund_name), pick non-null attributes.
    select
        company
        , fund_name
        , max(fund_code) as fund_code
        , max(jse_code) as jse_code
    from funds_raw
    group by company, fund_name

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'fund_name']) }} as fund_sk
        , company
        , fund_name
        , fund_code
        , jse_code
        , case when jse_code is not null then 'ETF' else 'UNIT_TRUST' end as fund_type
        , current_timestamp() as _loaded_at
    from deduped

)

select * from final
