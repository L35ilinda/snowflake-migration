{#
    Returns a list of post_hook SQL statements that attach
    RAP_TENANT_ISOLATION to {{ this }} on the `company` column. Idempotent
    via DROP ALL ROW ACCESS POLICIES — Snowflake errors if you ADD while a
    policy is already attached, and DROP ALL is the safe wipe before re-add.

    Gated by the caller via `target.database == 'ANALYTICS_DEV'` so CI runs
    against ANALYTICS_CI no-op cleanly. See ADR-0020.

    Usage in a model:

        {% set apply_rap = target.database == 'ANALYTICS_DEV' %}
        {{ config(post_hook=(attach_rap_tenant_isolation() if apply_rap else [])) }}
#}
{% macro attach_rap_tenant_isolation() %}
    {% set policy_fqn = 'ANALYTICS_DEV.CORE.RAP_TENANT_ISOLATION' %}
    {{ return([
        "alter table {{ this }} drop all row access policies",
        "alter table {{ this }} add row access policy " ~ policy_fqn ~ " on (company)",
    ]) }}
{% endmacro %}