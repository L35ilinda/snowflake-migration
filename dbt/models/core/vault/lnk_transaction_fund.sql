{#
    lnk_transaction_fund — investment-side link between hub_transaction
    and hub_fund. Same shape as lnk_transaction_client.
#}

{{ config(unique_key='transaction_fund_hk', tags=['vault']) }}

with new_pairs as (

    select distinct
        company
        , transaction_id
        , fund_code
    from {{ ref('fct_transactions') }}
    where transaction_id is not null
      and fund_code is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'fund_code']) }} as transaction_fund_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'fund_code']) }} as fund_hk
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_pairs

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'fund_code']) }}
      not in (select transaction_fund_hk from {{ this }})
{% endif %}
