{#
    hub_transaction — one row per (company, transaction_id) business key.
    Source: fct_transactions (per ADR-0015). Excludes rows where
    transaction_id is null (~8% of fact rows; see fct_transactions notes).
    Insert-only via incremental + NOT IN guard on transaction_hk.
#}

{{ config(unique_key='transaction_hk', tags=['vault']) }}

with new_keys as (

    select distinct
        company
        , transaction_id
    from {{ ref('fct_transactions') }}
    where transaction_id is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
    , company
    , transaction_id
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_keys

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }}
      not in (select transaction_hk from {{ this }})
{% endif %}
