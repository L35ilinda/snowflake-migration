with source as (

    select * from {{ source('raw_main_book', 'main_book_inv_commissions') }}

)

, renamed as (

    select
        commission_id
        , policy_number
        , advisor_identifier
        , business_line
        , commission_type
        , transaction_date::date                as transaction_date
        , gross_amount::number(18, 2)           as gross_amount
        , vat_amount::number(18, 2)             as vat_amount
        , net_amount::number(18, 2)             as net_amount
        , product_code
        , commission_rate::number(8, 4)         as commission_rate
        , clawback_reason
        , payment_reference
        , payment_date::date                    as payment_date
        , brokerage_split::number(8, 4)         as brokerage_split
        , status
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , _loaded_at
    from source

)

select * from renamed
