{%- test expect_row_values_to_have_data_for_every_n_datepart(model,
                                                                    date_col,
                                                                    date_part="day",
                                                                    interval=None,
                                                                    row_condition=None,
                                                                    test_start_date=None,
                                                                    test_end_date=None) -%}
{% if not execute %}
    {{ return('') }}
{% endif %}

{% if not test_start_date or not test_end_date %}
    {% set sql %}

        select
            min({{ date_col }}) as start_{{ date_part }},
            max({{ date_col }}) as end_{{ date_part }}
        from {{ model }}
        {% if row_condition %}
        where {{ row_condition }}
        {% endif %}

    {% endset %}

    {%- set dr = run_query(sql) -%}
    {%- set db_start_date = dr.columns[0].values()[0].strftime('%Y-%m-%d') -%}
    {%- set db_end_date = dr.columns[1].values()[0].strftime('%Y-%m-%d') -%}

{% endif %}

{% if not test_start_date %}
{% set start_date = db_start_date %}
{% else %}
{% set start_date = test_start_date %}
{% endif %}


{% if not test_end_date %}
{% set end_date = db_end_date %}
{% else %}
{% set end_date = test_end_date %}
{% endif %}

with base_dates as (

    {{ dbt_date.get_base_dates(start_date=start_date, end_date=end_date, datepart=date_part) }}
    {% if interval %}
    where mod(
            cast(
                {{dbt_utils.datediff("'"~start_date~"'", 'date_' ~ date_part, "'"~date_part~"'")}} 
                as {{ dbt_utils.type_int() }}
            ),
            cast({{interval}} as {{ dbt_utils.type_int() }})
        ) = 0
    {% endif %}
    
),

{% if interval %}
base_date_windows as (

    select
        cast(date_{{ date_part }} as {{ dbt_expectations.type_datetime() }}) as date_{{ date_part }},
        cast(lead(date_{{ date_part }}) over (order by date_{{ date_part }}) as {{ dbt_expectations.type_datetime() }}) as interval_end
    from base_dates

),
{% endif %}

model_data as (

    select
        cast({{ dbt_utils.date_trunc(date_part, date_col) }} as {{ dbt_expectations.type_datetime() }}) as date_{{ date_part }},
        count(*) as row_cnt
    from
        {{ model }} f
    {% if row_condition %}
    where {{ row_condition }}
    {% endif %}
    group by
        date_{{date_part}}

),

final as (
    
    select
        cast(d.date_{{ date_part }} as {{ dbt_expectations.type_datetime() }}) as date_{{ date_part }},
        case when f.date_{{ date_part }} is null then true else false end as is_missing,

    {% if not interval %}

        coalesce(f.row_cnt, 0) as row_cnt
    from 
        base_dates d
        left join 
        model_data f on cast(d.date_{{ date_part }} as {{ dbt_expectations.type_datetime() }}) = f.date_{{ date_part }}

    {% else %}
    
        sum(coalesce(f.row_cnt, 0)) as row_cnt
    from 
        base_date_windows d
        left join model_data f 
            on f.date_{{ date_part }} >= d.date_{{ date_part }} and f.date_{{ date_part }} < d.interval_end
    {{dbt_utils.group_by(2)}}

    {% endif %}

)
select
    *
from final
where
    row_cnt = 0
{%- endtest -%}
