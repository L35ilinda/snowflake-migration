{#
    Type 2 history view over snp_dim_policy. See ADR-0015.

    `dim_policy.sql` (Type 1, current state) is the model the four fact
    tables join to. This view is the parallel Type-2-history surface for
    anyone who needs to see how a policy looked at a point in time.

    Maps dbt's snapshot bookkeeping to the project's existing valid_from /
    valid_to / is_current convention so consumers don't have to learn
    `dbt_valid_from` / `dbt_valid_to`.

    Materialised as view rather than table — snapshot is the source of
    truth and is already a table; a second physical copy adds storage for
    no real benefit at this scale.
#}

{{ config(materialized='view') }}

with snapshot_rows as (

    select * from {{ ref('snp_dim_policy') }}

)

, projected as (

    select
        policy_sk
        , company
        , policy_number
        , policy_universe
        , inception_date
        , policy_status
        , member_id
        , age_next
        , smoker_status
        , income_bracket
        , product_name
        , life_sum_assured
        , life_premium
        , disability_type
        , disability_sum_assured
        , disability_premium
        , chronic_level
        , chronic_waiting_period
        , chronic_premium
        , accident_benefit
        , accident_premium
        , total_monthly_premium
        , commission_rate

        -- Project Type 2 metadata in the project's house style.
        , dbt_valid_from                                            as valid_from
        , coalesce(dbt_valid_to, '9999-12-31 00:00:00'::timestamp_ntz) as valid_to
        , (dbt_valid_to is null)                                    as is_current

        , dbt_scd_id                                                as policy_version_id
        , dbt_updated_at                                            as version_recorded_at
        , _loaded_at
    from snapshot_rows

)

select * from projected
