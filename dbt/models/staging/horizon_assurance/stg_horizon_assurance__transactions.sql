with source as (

    select * from {{ source('raw_horizon_assurance', 'horizon_transactions') }}

)

, renamed as (

    select
        transaction_id
        , policy_number
        , client_id_number
        , fund_code
        , transaction_type
        , transaction_date::date            as transaction_date
        , amount::number(18, 2)             as amount
        , units::number(18, 4)              as units
        , price_per_unit::number(18, 4)     as price_per_unit
        , status
        , reference_number
        , source_fund
        , narrative
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , _loaded_at
    from source

)

select * from renamed
