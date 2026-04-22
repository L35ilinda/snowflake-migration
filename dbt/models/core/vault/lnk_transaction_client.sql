{#
    lnk_transaction_client — investment-side relationship between
    hub_transaction and hub_client (risk transactions don't carry
    client_id_number, so this link is naturally smaller than
    lnk_transaction_policy).
#}

{{ config(unique_key='transaction_client_hk', tags=['vault']) }}

with new_pairs as (

    select distinct
        company
        , transaction_id
        , client_id_number
    from {{ ref('fct_transactions') }}
    where transaction_id is not null
      and client_id_number is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'client_id_number']) }} as transaction_client_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'client_id_number']) }} as client_hk
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_pairs

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'client_id_number']) }}
      not in (select transaction_client_hk from {{ this }})
{% endif %}
