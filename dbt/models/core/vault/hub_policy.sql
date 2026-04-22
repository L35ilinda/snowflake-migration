{#
    hub_policy — one row per (company, policy_number).
    Sourced from fct_transactions per ADR-0015 (transaction-touched
    policies only). Same hash formula as dim_policy.policy_sk so the two
    keys are interoperable for ad-hoc joins.
#}

{{ config(unique_key='policy_hk', tags=['vault']) }}

with new_keys as (

    select distinct
        company
        , policy_number
    from {{ ref('fct_transactions') }}
    where policy_number is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }} as policy_hk
    , company
    , policy_number
    , '{{ run_started_at }}'::timestamp_ntz as load_dts
    , 'fct_transactions' as record_source
from new_keys

{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['company', 'policy_number']) }}
      not in (select policy_hk from {{ this }})
{% endif %}
