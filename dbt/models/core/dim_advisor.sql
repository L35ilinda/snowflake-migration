{#
    Conformed advisor dimension.

    Union advisor_identifier across all three tenants from commission and
    valuation staging models. Dedupe on (company, advisor_identifier).
    Surrogate key is a hash of (company, advisor_identifier) so the same
    advisor ID in different tenants is treated as different entities
    (advisor IDs are not globally unique across companies).
#}

with advisors_union as (

    -- Main Book
    select
        'MAIN_BOOK' as company
        , advisor_identifier
    from {{ ref('stg_main_book__ins_commissions') }}
    where advisor_identifier is not null

    union all select 'MAIN_BOOK', advisor_identifier
    from {{ ref('stg_main_book__inv_commissions') }}
    where advisor_identifier is not null

    union all select 'MAIN_BOOK', advisor_identifier
    from {{ ref('stg_main_book__valuations') }}
    where advisor_identifier is not null

    union all select 'MAIN_BOOK', advisor_identifier
    from {{ ref('stg_main_book__risk_benefits') }}
    where advisor_identifier is not null

    -- Indigo Insurance
    union all select 'INDIGO_INSURANCE', advisor_identifier
    from {{ ref('stg_indigo_insurance__ins_commissions') }}
    where advisor_identifier is not null

    union all select 'INDIGO_INSURANCE', advisor_identifier
    from {{ ref('stg_indigo_insurance__inv_commissions') }}
    where advisor_identifier is not null

    union all select 'INDIGO_INSURANCE', advisor_identifier
    from {{ ref('stg_indigo_insurance__valuations') }}
    where advisor_identifier is not null

    union all select 'INDIGO_INSURANCE', advisor_identifier
    from {{ ref('stg_indigo_insurance__insurance') }}
    where advisor_identifier is not null

    -- Horizon Assurance
    union all select 'HORIZON_ASSURANCE', advisor_identifier
    from {{ ref('stg_horizon_assurance__ins_commissions') }}
    where advisor_identifier is not null

    union all select 'HORIZON_ASSURANCE', advisor_identifier
    from {{ ref('stg_horizon_assurance__inv_commissions') }}
    where advisor_identifier is not null

    union all select 'HORIZON_ASSURANCE', advisor_identifier
    from {{ ref('stg_horizon_assurance__valuations') }}
    where advisor_identifier is not null

    union all select 'HORIZON_ASSURANCE', advisor_identifier
    from {{ ref('stg_horizon_assurance__assurance') }}
    where advisor_identifier is not null

)

, deduped as (

    select distinct
        company
        , advisor_identifier
    from advisors_union

)

, final as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'advisor_identifier']) }} as advisor_sk
        , advisor_identifier
        , company
        , current_timestamp() as _loaded_at
    from deduped

)

select * from final
