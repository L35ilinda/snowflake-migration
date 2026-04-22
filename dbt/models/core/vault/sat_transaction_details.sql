{#
    sat_transaction_details — descriptive attributes (low churn).
    Type 2 versioning via hashdiff: a new sat row is inserted only when
    the attribute payload differs from the latest version already in the
    table for that transaction_hk. Without the hashdiff guard, every run
    would append 100% duplicates.

    Strategy: `append` (not `merge`) — sats are insert-only by design.
#}

{{ config(
    materialized='incremental',
    incremental_strategy='append',
    tags=['vault'],
) }}

with source_state as (

    select
        {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
        , transaction_type
        , transaction_date
        , status
        , reference_number
        , narrative
        , claim_type
        , claim_reason
        , benefit_affected
        , transaction_category
        , '{{ run_started_at }}'::timestamp_ntz as load_dts
        , 'fct_transactions' as record_source
        , md5(
            coalesce(transaction_type, '') || '|' ||
            coalesce(transaction_date::varchar, '') || '|' ||
            coalesce(status, '') || '|' ||
            coalesce(reference_number, '') || '|' ||
            coalesce(narrative, '') || '|' ||
            coalesce(claim_type, '') || '|' ||
            coalesce(claim_reason, '') || '|' ||
            coalesce(benefit_affected, '') || '|' ||
            coalesce(transaction_category, '')
        ) as hashdiff
    from {{ ref('fct_transactions') }}
    where transaction_id is not null

)

{% if is_incremental() %}

, latest_in_target as (

    -- Most recent hashdiff per transaction_hk currently in the sat.
    select
        transaction_hk
        , hashdiff
    from {{ this }}
    qualify row_number() over (partition by transaction_hk order by load_dts desc) = 1

)

select s.*
from source_state s
left join latest_in_target t using (transaction_hk)
where t.hashdiff is null               -- new transaction
   or t.hashdiff <> s.hashdiff         -- attributes changed

{% else %}

select * from source_state

{% endif %}
