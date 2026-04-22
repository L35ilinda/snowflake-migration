{#
    sat_transaction_amounts — financial measures (higher churn).
    Split from sat_transaction_details so a restated amount doesn't
    re-version unrelated descriptive metadata. Same hashdiff-guarded
    insert-only pattern.
#}

{{ config(
    materialized='incremental',
    incremental_strategy='append',
    tags=['vault'],
) }}

with source_state as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
        , amount
        , units
        , price_per_unit
        , '{{ run_started_at }}'::timestamp_ntz as load_dts
        , 'fct_transactions' as record_source
        , md5(
            coalesce(amount::varchar, '') || '|' ||
            coalesce(units::varchar, '') || '|' ||
            coalesce(price_per_unit::varchar, '')
        ) as hashdiff
    from {{ ref('fct_transactions') }}
    where transaction_id is not null

)

{% if is_incremental() %}

, latest_in_target as (

    select
        transaction_hk
        , hashdiff
    from {{ this }}
    qualify row_number() over (partition by transaction_hk order by load_dts desc) = 1

)

select s.*
from source_state s
left join latest_in_target t using (transaction_hk)
where t.hashdiff is null
   or t.hashdiff <> s.hashdiff

{% else %}

select * from source_state

{% endif %}
