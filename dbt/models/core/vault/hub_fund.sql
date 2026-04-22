{#
    hub_fund — one row per (company, fund_code).
    Only investment transactions populate fund_code (risk transactions
    don't). Same composite-key pattern as hub_client.
#}

{{ config(unique_key='fund_hk', tags=['vault']) }}

with new_keys as (

    select distinct
        company
        , fund_code
    from {{ ref('fct_transactions') }}
    where fund_code is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'fund_code']) }} as fund_hk
    , company
    , fund_code
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_keys

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'fund_code']) }}
      not in (select fund_hk from {{ this }})
{% endif %}
