{#
    Type 2 snapshot of dim_policy. See ADR-0015.

    Strategy: `check` on a curated attribute set rather than `all`. Picks
    columns that actually carry meaningful change: status, sums assured,
    premiums, commission rate, and the descriptive fields a CRM update
    would touch. Excludes _loaded_at / valid_* / is_current to avoid
    manufacturing history rows from re-runs that don't change source data.

    `timestamp` strategy was rejected because dim_policy._loaded_at is per
    row, not per business key — same policy can re-load with the same
    underlying values multiple times.

    Schema/database honor target.database + DBT_SCHEMA_PREFIX (set in CI)
    so the same definition works in dev (ANALYTICS_DEV.CORE) and CI
    (ANALYTICS_CI.PR_<n>_CORE). Defaults are in dbt_project.yml's
    `snapshots:` block; we only override unique_key and strategy here.
#}

{% snapshot snp_dim_policy %}

{{
    config(
      unique_key='policy_sk',
      strategy='check',
      check_cols=[
          'policy_status',
          'product_name',
          'member_id',
          'income_bracket',
          'smoker_status',
          'age_next',
          'life_sum_assured',
          'life_premium',
          'disability_type',
          'disability_sum_assured',
          'disability_premium',
          'chronic_level',
          'chronic_waiting_period',
          'chronic_premium',
          'accident_benefit',
          'accident_premium',
          'total_monthly_premium',
          'commission_rate',
      ],
      invalidate_hard_deletes=False,
    )
}}

select * from {{ ref('dim_policy') }}

{% endsnapshot %}
