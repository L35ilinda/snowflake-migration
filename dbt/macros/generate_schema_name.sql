{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Use the custom schema name directly (STAGING, CORE, MARTS) instead of
        dbt's default behaviour of prepending the target schema as a prefix.

        Optionally prefix with `DBT_SCHEMA_PREFIX` env var — CI sets this to
        `PR_<number>_` to isolate PR builds from each other and from `main`
        builds. Empty string (default) means "no prefix", which is what local
        dev and the deploy-to-dev workflow use.
    #}
    {%- set schema_prefix = env_var('DBT_SCHEMA_PREFIX', '') | upper -%}
    {%- if custom_schema_name is none -%}
        {{ schema_prefix }}{{ target.schema }}
    {%- else -%}
        {{ schema_prefix }}{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
