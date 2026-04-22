{#
    hub_client — one row per (company, client_id_number).
    Investment transactions only carry client_id_number; risk transactions
    don't. Hub will be smaller than hub_policy as a result.
#}

{{ config(unique_key='client_hk', tags=['vault']) }}

with new_keys as (

    select distinct
        company
        , client_id_number
    from {{ ref('fct_transactions') }}
    where client_id_number is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'client_id_number']) }} as client_hk
    , company
    , client_id_number
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_keys

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'client_id_number']) }}
      not in (select client_hk from {{ this }})
{% endif %}
