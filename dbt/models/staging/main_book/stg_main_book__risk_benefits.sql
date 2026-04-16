with source as (

    select * from {{ source('raw_main_book', 'main_book_risk_benefits') }}

)

, renamed as (

    select
        -- PascalCase columns renamed to snake_case
        policynumber                                as policy_number
        , inceptiondate::date                       as inception_date
        , policystatus                              as policy_status
        , memberid                                  as member_id
        , agenext::int                              as age_next
        , smokerstatus                              as smoker_status
        , incomebrackets                            as income_bracket
        , life_sumassured::number(18, 2)            as life_sum_assured
        , life_premium::number(18, 2)               as life_premium
        , disability_type
        , disability_sumassured::number(18, 2)      as disability_sum_assured
        , disability_premium::number(18, 2)         as disability_premium
        , chronic_level
        , chronic_waitingperiod                     as chronic_waiting_period
        , chronic_premium::number(18, 2)            as chronic_premium
        , accident_benefit::number(18, 2)           as accident_benefit
        , accident_premium::number(18, 2)           as accident_premium
        , total_monthlypremium::number(18, 2)       as total_monthly_premium
        , commission_rate::number(8, 4)             as commission_rate
        , advisor_identifier
        , client_title
        , client_first_name
        , client_surname
        , client_initials
        , _loaded_at
    from source

)

select * from renamed
