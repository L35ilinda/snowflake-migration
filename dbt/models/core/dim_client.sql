{#
    Masking policies live in ANALYTICS_DEV.CORE and are applied only when
    building into ANALYTICS_DEV. The CI target writes to ANALYTICS_CI, a
    transient sandbox that does not hold its own policies; masking is a
    property of real environments, not CI. See ADR-0009.
#}
{% set apply_masking = target.database == 'ANALYTICS_DEV' %}

{{
    config(
        post_hook=(
            [
                "alter table {{ this }} alter column client_id_number set masking policy ANALYTICS_DEV.CORE.MP_MASK_STRING_PII",
                "alter table {{ this }} alter column client_first_name set masking policy ANALYTICS_DEV.CORE.MP_MASK_STRING_PII",
                "alter table {{ this }} alter column client_surname set masking policy ANALYTICS_DEV.CORE.MP_MASK_STRING_PII",
                "alter table {{ this }} alter column client_full_name set masking policy ANALYTICS_DEV.CORE.MP_MASK_STRING_PII",
                "alter table {{ this }} alter column birth_date set masking policy ANALYTICS_DEV.CORE.MP_MASK_DATE_PII",
            ] if apply_masking else []
        )
    )
}}

{#
    Conformed client dimension.

    Sources: valuations + transactions staging tables (the only tables that
    carry client_id_number). Commissions, risk benefits, and insurance tables
    do not have client IDs, so those facts will need a bridge via
    policy_number in a later iteration.

    Natural key: (company, client_id_number). IDs may not be globally unique
    across tenants.

    PII columns: client_first_name, client_surname, client_initials,
    client_id_number, birth_date. These should be covered by a Snowflake
    dynamic masking policy before exposing to BI or analyst roles.

    ID parsing: the first 6 digits of the ID number look like YYMMDD.
    Century rule: YY between 00-29 → 2000s, else 1900s. If parsing fails
    (malformed ID), birth_date is null.
#}

with clients_union as (

    select
        'MAIN_BOOK' as company
        , client_id_number
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , _loaded_at
    from {{ ref('stg_main_book__valuations') }}
    where client_id_number is not null

    union all select 'MAIN_BOOK', client_id_number, client_title,
        client_first_name, client_surname, client_initials, _loaded_at
    from {{ ref('stg_main_book__valuation_transactions') }}
    where client_id_number is not null

    union all select 'INDIGO_INSURANCE', client_id_number, client_title,
        client_first_name, client_surname, client_initials, _loaded_at
    from {{ ref('stg_indigo_insurance__valuations') }}
    where client_id_number is not null

    union all select 'INDIGO_INSURANCE', client_id_number, client_title,
        client_first_name, client_surname, client_initials, _loaded_at
    from {{ ref('stg_indigo_insurance__transactions') }}
    where client_id_number is not null

    union all select 'HORIZON_ASSURANCE', client_id_number, client_title,
        client_first_name, client_surname, client_initials, _loaded_at
    from {{ ref('stg_horizon_assurance__valuations') }}
    where client_id_number is not null

    union all select 'HORIZON_ASSURANCE', client_id_number, client_title,
        client_first_name, client_surname, client_initials, _loaded_at
    from {{ ref('stg_horizon_assurance__transactions') }}
    where client_id_number is not null

)

, deduped as (

    -- One row per (company, client_id_number). MAX picks a canonical
    -- attribute value when the same client has slightly different entries
    -- across source tables (e.g. null title in one place).
    select
        company
        , client_id_number
        , max(client_title)       as client_title
        , max(client_first_name)  as client_first_name
        , max(client_surname)     as client_surname
        , max(client_initials)    as client_initials
    from clients_union
    group by company, client_id_number

)

, enriched as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'client_id_number']) }} as client_sk
        , company
        , client_id_number
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , trim(
            coalesce(client_title || ' ', '')
            || coalesce(client_first_name || ' ', '')
            || coalesce(client_surname, '')
          ) as client_full_name

        -- Birth date from ID (YYMMDD). Century rule: 00-29 → 2000s else 1900s.
        , try_to_date(
            case
              when regexp_like(left(client_id_number, 6), '^[0-9]{6}$') then
                case
                  when try_to_number(left(client_id_number, 2)) <= 29
                    then '20' || left(client_id_number, 6)
                  else '19' || left(client_id_number, 6)
                end
            end,
            'YYYYMMDD'
          ) as birth_date

        , current_timestamp() as _loaded_at
    from deduped

)

, final as (

    select
        client_sk
        , company
        , client_id_number
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , client_full_name
        , birth_date
        , case
            when birth_date is not null
              then datediff('year', birth_date, current_date())
          end as age_years
        , _loaded_at
    from enriched

)

select * from final
