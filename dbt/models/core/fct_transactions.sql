{#
    Conformed transactions fact.

    Two transaction universes:
      - RISK:       from stg_*__risk_benefits_transactions / ins_transactions.
                    Columns: transaction_id, policy_number, member_id,
                    transaction_type, transaction_date, amount, status,
                    reference_number, narrative, claim_type, claim_reason,
                    benefit_affected.
      - INVESTMENT: from stg_*__valuation_transactions / transactions.
                    Columns: transaction_id, policy_number, client_id_number,
                    fund_code, transaction_type, transaction_date, amount,
                    units, price_per_unit, status, reference_number,
                    source_fund, narrative.

    Union into a single fact with `transaction_category` column.
    Universe-specific columns are null for the other universe.

    Grain: one row per transaction. transaction_sk = hash(company, transaction_id).

    FKs:
      - policy_sk  → dim_policy on (company, policy_number)
      - client_sk  → dim_client on (company, client_id_number) — investment only
      - fund_sk    → dim_fund on (company, fund_code) via lookup — investment only
      - date_sk    → dim_date on transaction_date
#}

with risk_txns as (

    select
        'MAIN_BOOK' as company
        , 'RISK' as transaction_category
        , transaction_id
        , policy_number
        , member_id
        , cast(null as varchar) as client_id_number
        , cast(null as varchar) as fund_code_natural
        , transaction_type
        , transaction_date
        , amount
        , cast(null as number(18, 4)) as units
        , cast(null as number(18, 4)) as price_per_unit
        , status
        , reference_number
        , cast(null as varchar) as source_fund
        , narrative
        , claim_type
        , claim_reason
        , benefit_affected
        , _loaded_at
    from {{ ref('stg_main_book__risk_benefits_transactions') }}

    union all select
        'INDIGO_INSURANCE', 'RISK', transaction_id, policy_number, member_id,
        null, null, transaction_type, transaction_date, amount, null, null,
        status, reference_number, null, narrative, claim_type, claim_reason,
        benefit_affected, _loaded_at
    from {{ ref('stg_indigo_insurance__ins_transactions') }}

    union all select
        'HORIZON_ASSURANCE', 'RISK', transaction_id, policy_number, member_id,
        null, null, transaction_type, transaction_date, amount, null, null,
        status, reference_number, null, narrative, claim_type, claim_reason,
        benefit_affected, _loaded_at
    from {{ ref('stg_horizon_assurance__ins_transactions') }}

)

, investment_txns as (

    select
        'MAIN_BOOK' as company
        , 'INVESTMENT' as transaction_category
        , transaction_id
        , policy_number
        , cast(null as varchar) as member_id
        , client_id_number
        , fund_code as fund_code_natural
        , transaction_type
        , transaction_date
        , amount
        , units
        , price_per_unit
        , status
        , reference_number
        , source_fund
        , narrative
        , cast(null as varchar) as claim_type
        , cast(null as varchar) as claim_reason
        , cast(null as varchar) as benefit_affected
        , _loaded_at
    from {{ ref('stg_main_book__valuation_transactions') }}

    union all select
        'INDIGO_INSURANCE', 'INVESTMENT', transaction_id, policy_number, null,
        client_id_number, fund_code, transaction_type, transaction_date, amount,
        units, price_per_unit, status, reference_number, source_fund, narrative,
        null, null, null, _loaded_at
    from {{ ref('stg_indigo_insurance__transactions') }}

    union all select
        'HORIZON_ASSURANCE', 'INVESTMENT', transaction_id, policy_number, null,
        client_id_number, fund_code, transaction_type, transaction_date, amount,
        units, price_per_unit, status, reference_number, source_fund, narrative,
        null, null, null, _loaded_at
    from {{ ref('stg_horizon_assurance__transactions') }}

)

, all_txns_raw as (
    select * from risk_txns
    union all
    select * from investment_txns
)

, all_txns as (

    -- ~8% of transactions have null transaction_id. Disambiguate so every
    -- row is uniquely addressable; flag rows with complete natural keys.
    select
        *
        , row_number() over (
            partition by company, coalesce(transaction_id, '_NULL_')
            order by transaction_date nulls last, amount, _loaded_at
          ) as _row_in_grain
        , case when transaction_id is not null then true else false end as has_complete_grain
    from all_txns_raw

)

{#-
    Resolve fund_code → fund_name via dim_fund lookup. Investment transactions
    carry fund_code; dim_fund.fund_code is a (non-unique, nullable) attribute
    within a company. We resolve by joining on (company, fund_code) and picking
    the fund_name that matches. If multiple names map to the same code (rare),
    the min alphabetical is taken for determinism.
-#}
, fund_lookup as (

    select
        company
        , fund_code
        , min(fund_name) as fund_name
    from {{ ref('dim_fund') }}
    where fund_code is not null
    group by company, fund_code

)

, with_sks as (

    select
        {{ dbt_utils.generate_surrogate_key(['t.company', 't.transaction_id', 't._row_in_grain']) }} as transaction_sk

        -- FKs
        , case when t.policy_number is not null
            then {{ dbt_utils.generate_surrogate_key(['t.company', 't.policy_number']) }}
          end as policy_sk

        , case when t.client_id_number is not null
            then {{ dbt_utils.generate_surrogate_key(['t.company', 't.client_id_number']) }}
          end as client_sk

        , case when fl.fund_name is not null
            then {{ dbt_utils.generate_surrogate_key(['t.company', 'fl.fund_name']) }}
          end as fund_sk

        , case when t.transaction_date is not null
            then to_char(t.transaction_date, 'YYYYMMDD')::int
          end as date_sk

        -- Degenerate + descriptive
        , t.company
        , t.transaction_category
        , t.transaction_id
        , t.policy_number
        , t.member_id
        , t.client_id_number
        , t.fund_code_natural as fund_code
        , t.transaction_type
        , t.transaction_date
        , t.status
        , t.reference_number
        , t.source_fund
        , t.narrative
        , t.claim_type
        , t.claim_reason
        , t.benefit_affected

        , t.has_complete_grain

        -- Measures
        , t.amount
        , t.units
        , t.price_per_unit

        , t._loaded_at
    from all_txns t
    left join fund_lookup fl
      on t.company = fl.company and t.fund_code_natural = fl.fund_code

)

select * from with_sks
