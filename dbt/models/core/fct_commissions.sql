{#
    Conformed commissions fact.

    Union all 6 commission staging views (ins_commissions + inv_commissions
    across 3 tenants). Grain: one row per commission payout.

    Adds:
      - commission_sk: surrogate key on (company, commission_id)
      - advisor_sk: FK to dim_advisor on (company, advisor_identifier)
      - company: source tenant
      - commission_category: derived from source (INSURANCE / INVESTMENT)
#}

with commissions_union as (

    -- Main Book
    select
        'MAIN_BOOK' as company
        , 'INSURANCE' as commission_category
        , commission_id
        , policy_number
        , advisor_identifier
        , business_line
        , commission_type
        , transaction_date
        , gross_amount
        , vat_amount
        , net_amount
        , product_code
        , commission_rate
        , clawback_reason
        , payment_reference
        , payment_date
        , brokerage_split
        , status
        , _loaded_at
    from {{ ref('stg_main_book__ins_commissions') }}

    union all select
        'MAIN_BOOK', 'INVESTMENT', commission_id, policy_number, advisor_identifier,
        business_line, commission_type, transaction_date, gross_amount, vat_amount,
        net_amount, product_code, commission_rate, clawback_reason, payment_reference,
        payment_date, brokerage_split, status, _loaded_at
    from {{ ref('stg_main_book__inv_commissions') }}

    -- Indigo Insurance
    union all select
        'INDIGO_INSURANCE', 'INSURANCE', commission_id, policy_number, advisor_identifier,
        business_line, commission_type, transaction_date, gross_amount, vat_amount,
        net_amount, product_code, commission_rate, clawback_reason, payment_reference,
        payment_date, brokerage_split, status, _loaded_at
    from {{ ref('stg_indigo_insurance__ins_commissions') }}

    union all select
        'INDIGO_INSURANCE', 'INVESTMENT', commission_id, policy_number, advisor_identifier,
        business_line, commission_type, transaction_date, gross_amount, vat_amount,
        net_amount, product_code, commission_rate, clawback_reason, payment_reference,
        payment_date, brokerage_split, status, _loaded_at
    from {{ ref('stg_indigo_insurance__inv_commissions') }}

    -- Horizon Assurance
    union all select
        'HORIZON_ASSURANCE', 'INSURANCE', commission_id, policy_number, advisor_identifier,
        business_line, commission_type, transaction_date, gross_amount, vat_amount,
        net_amount, product_code, commission_rate, clawback_reason, payment_reference,
        payment_date, brokerage_split, status, _loaded_at
    from {{ ref('stg_horizon_assurance__ins_commissions') }}

    union all select
        'HORIZON_ASSURANCE', 'INVESTMENT', commission_id, policy_number, advisor_identifier,
        business_line, commission_type, transaction_date, gross_amount, vat_amount,
        net_amount, product_code, commission_rate, clawback_reason, payment_reference,
        payment_date, brokerage_split, status, _loaded_at
    from {{ ref('stg_horizon_assurance__inv_commissions') }}

)

, enriched as (

    select
        {{ dbt_utils.generate_surrogate_key(['c.company', 'c.commission_id']) }} as commission_sk
        , {{ dbt_utils.generate_surrogate_key(['c.company', 'c.advisor_identifier']) }} as advisor_sk
        , case when c.policy_number is not null
            then {{ dbt_utils.generate_surrogate_key(['c.company', 'c.policy_number']) }}
          end as policy_sk
        , case when c.transaction_date is not null
            then to_char(c.transaction_date, 'YYYYMMDD')::int
          end as date_sk
        , c.company
        , c.commission_category
        , c.commission_id
        , c.policy_number
        , c.advisor_identifier
        , c.business_line
        , c.commission_type
        , c.transaction_date
        , c.gross_amount
        , c.vat_amount
        , c.net_amount
        , c.product_code
        , c.commission_rate
        , c.clawback_reason
        , c.payment_reference
        , c.payment_date
        , c.brokerage_split
        , c.status
        , c._loaded_at
    from commissions_union c

)

select * from enriched
