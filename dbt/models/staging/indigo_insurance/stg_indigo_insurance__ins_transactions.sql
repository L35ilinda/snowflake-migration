with source as (

    select * from {{ source('raw_indigo_insurance', 'indigo_ins_transactions') }}

)

, renamed as (

    select
        transaction_id
        , policy_number
        , member_id
        , transaction_type
        , transaction_date::date        as transaction_date
        , amount::number(18, 2)         as amount
        , status
        , reference_number
        , narrative
        , claim_type
        , claim_reason
        , benefit_affected
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , _loaded_at
    from source

)

select * from renamed
