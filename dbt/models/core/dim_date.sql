{#
    Conformed date dimension.

    Range: 2015-01-01 through 2030-12-31, covering the earliest policy
    inception_date (2015) plus future headroom. Built with dbt_utils.date_spine.

    date_sk is YYYYMMDD integer — human-readable, sortable, and natural for
    joins (facts store transaction_date etc. as DATE; convert with
    to_char(d, 'YYYYMMDD')::int at query time, or we can expose a separate
    date key from facts later).

    Fiscal year: South African tax year starts 1 March. fy_start_month = 3.
#}

with dates as (

    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="to_date('2015-01-01')",
        end_date="to_date('2031-01-01')"
    ) }}

)

, final as (

    select
        date_day                                                as date_day
        , to_char(date_day, 'YYYYMMDD')::int                    as date_sk
        , year(date_day)                                        as year
        , quarter(date_day)                                     as quarter
        , month(date_day)                                       as month
        , monthname(date_day)                                   as month_name
        , day(date_day)                                         as day_of_month
        , dayofweek(date_day)                                   as day_of_week    -- 0 = Sunday
        , dayname(date_day)                                     as day_name
        , weekofyear(date_day)                                  as week_of_year
        , dayofyear(date_day)                                   as day_of_year
        , case when dayofweek(date_day) in (0, 6) then true else false end as is_weekend
        , case when last_day(date_day) = date_day then true else false end as is_month_end
        , case
            when month(date_day) >= 3 then year(date_day)
            else year(date_day) - 1
          end                                                   as fiscal_year
        , case
            when month(date_day) between 3 and 5 then 1
            when month(date_day) between 6 and 8 then 2
            when month(date_day) between 9 and 11 then 3
            else 4
          end                                                   as fiscal_quarter
        , date_trunc('month', date_day)::date                   as month_start
        , last_day(date_day)                                    as month_end
        , date_trunc('quarter', date_day)::date                 as quarter_start
        , date_trunc('year', date_day)::date                    as year_start
    from dates

)

select * from final
