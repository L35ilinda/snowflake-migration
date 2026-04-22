{#
    lnk_transaction_policy — relationship between hub_transaction and
    hub_policy. Effectively 1:1 in this dataset (a single transaction
    references at most one policy) but Vault models the relationship
    cardinality without assuming it.
#}

{{ config(unique_key='transaction_policy_hk', tags=['vault']) }}

with new_pairs as (

    select distinct
        company
        , transaction_id
        , policy_number
    from {{ ref('fct_transactions') }}
    where transaction_id is not null
      and policy_number is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'policy_number']) }} as transaction_policy_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id']) }} as transaction_hk
    , {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_hk
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_pairs

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'transaction_id', 'policy_number']) }}
      not in (select transaction_policy_hk from {{ this }})
{% endif %}
