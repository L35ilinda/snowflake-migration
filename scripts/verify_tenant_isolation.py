"""
Acceptance test for ADR-0020 (RAP_TENANT_ISOLATION).

Connects to Snowflake once per role, runs `select count(*)` over a sample of
RAP-protected tables, and asserts each role sees the expected row totals:

- FR_ENGINEER and FR_ANALYST see all rows (current behaviour preserved).
- FR_ANALYST_<TENANT> sees only that tenant's rows.

Run after `terraform apply` + `dbt build` against ANALYTICS_DEV. Exits
non-zero on any unexpected count, suitable for CI gating later.

Usage:
    python scripts/verify_tenant_isolation.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import snowflake.connector
from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv

load_dotenv()

# Tables protected by RAP_TENANT_ISOLATION. Matches the post_hook list in
# dbt models. Tuple of (database, schema, table) — fully qualified to avoid
# session-context surprises when switching roles.
PROTECTED_TABLES = [
    ("ANALYTICS_DEV", "CORE", "DIM_ADVISOR"),
    ("ANALYTICS_DEV", "CORE", "DIM_CLIENT"),
    ("ANALYTICS_DEV", "CORE", "DIM_FUND"),
    ("ANALYTICS_DEV", "CORE", "DIM_POLICY"),
    ("ANALYTICS_DEV", "CORE", "DIM_PRODUCT"),
    ("ANALYTICS_DEV", "CORE", "DIM_POLICY_HISTORY"),
    ("ANALYTICS_DEV", "CORE", "FCT_COMMISSIONS"),
    ("ANALYTICS_DEV", "CORE", "FCT_POLICIES"),
    ("ANALYTICS_DEV", "CORE", "FCT_TRANSACTIONS"),
    ("ANALYTICS_DEV", "CORE", "FCT_VALUATIONS"),
    ("ANALYTICS_DEV", "MARTS", "FINANCE_ADVISOR_COMMISSIONS_MONTHLY"),
    ("ANALYTICS_DEV", "MARTS", "PORTFOLIO_AUM_MONTHLY"),
    ("ANALYTICS_DEV", "MARTS", "RISK_POLICY_INFORCE"),
]

# Tenants and the roles scoped to each.
TENANT_ROLES = {
    "MAIN_BOOK": "FR_ANALYST_MAIN_BOOK",
    "INDIGO_INSURANCE": "FR_ANALYST_INDIGO_INSURANCE",
    "HORIZON_ASSURANCE": "FR_ANALYST_HORIZON_ASSURANCE",
}

# Roles that should see all rows.
SEE_ALL_ROLES = ["FR_ENGINEER", "FR_ANALYST"]


def _load_pkey() -> bytes:
    key_path = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]).expanduser()
    passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
    pkey = serialization.load_pem_private_key(
        key_path.read_bytes(),
        password=passphrase.encode() if passphrase else None,
    )
    return pkey.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def _connect(role: str) -> snowflake.connector.SnowflakeConnection:
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=_load_pkey(),
        role=role,
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "BI_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "ANALYTICS_DEV"),
    )


def _count(cur, db: str, schema: str, table: str, *, where: str | None = None) -> int:
    sql = f'SELECT count(*) FROM "{db}"."{schema}"."{table}"'
    if where:
        sql += f" WHERE {where}"
    cur.execute(sql)
    return int(cur.fetchone()[0])


def _baseline_counts() -> dict[tuple[str, str, str], dict[str, int]]:
    """Get FR_ENGINEER's view: total rows + per-tenant rows for each table."""
    print("Collecting baseline counts as FR_ENGINEER ...")
    out: dict[tuple[str, str, str], dict[str, int]] = {}
    conn = _connect("FR_ENGINEER")
    try:
        cur = conn.cursor()
        for db, schema, tbl in PROTECTED_TABLES:
            key = (db, schema, tbl)
            out[key] = {"TOTAL": _count(cur, db, schema, tbl)}
            for tenant in TENANT_ROLES:
                out[key][tenant] = _count(
                    cur, db, schema, tbl, where=f"company = '{tenant}'"
                )
    finally:
        conn.close()
    return out


def _verify_role(
    role: str, baseline: dict, *, expected_tenant: str | None
) -> list[str]:
    """
    Verify counts for a role.

    expected_tenant=None  -> see all rows (FR_ENGINEER, FR_ANALYST)
    expected_tenant=<TENANT> -> see only that tenant's rows
    """
    failures: list[str] = []
    print(
        f"\nVerifying role={role}, expected={'all rows' if expected_tenant is None else expected_tenant + ' rows only'}"
    )
    conn = _connect(role)
    try:
        cur = conn.cursor()
        for (db, schema, tbl), counts in baseline.items():
            actual = _count(cur, db, schema, tbl)
            expected = (
                counts["TOTAL"] if expected_tenant is None else counts[expected_tenant]
            )
            ok = actual == expected
            marker = "OK " if ok else "FAIL"
            print(f"  [{marker}] {schema}.{tbl}: saw {actual}, expected {expected}")
            if not ok:
                failures.append(
                    f"{role} on {schema}.{tbl}: saw {actual}, expected {expected}"
                )
    finally:
        conn.close()
    return failures


def main() -> int:
    baseline = _baseline_counts()
    failures: list[str] = []

    for role in SEE_ALL_ROLES:
        failures.extend(_verify_role(role, baseline, expected_tenant=None))

    for tenant, role in TENANT_ROLES.items():
        failures.extend(_verify_role(role, baseline, expected_tenant=tenant))

    print("\n" + "=" * 60)
    if failures:
        print(f"FAILED — {len(failures)} mismatch(es):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("PASS — all roles see expected row counts. RAP_TENANT_ISOLATION live.")
    return 0


if __name__ == "__main__":
    sys.exit(main())