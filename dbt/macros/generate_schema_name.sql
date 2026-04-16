{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Use the custom schema name directly (STAGING, CORE, MARTS) instead of
        dbt's default behaviour of prepending the target schema as a prefix.
        If no custom schema is set, fall back to the target schema.
    #}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
