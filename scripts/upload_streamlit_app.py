"""
Upload the semantic-model YAML and Streamlit source files to the Snowflake
stage provisioned by the `snowflake_streamlit_analyst` Terraform module.

Run after `terraform apply` (or whenever the YAML / Python changes):

    python scripts/upload_streamlit_app.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv
import snowflake.connector

STAGE_FQN = "ANALYTICS_DEV.SEMANTIC.MODELS"
REPO_ROOT = Path(__file__).resolve().parent.parent

FILES_TO_UPLOAD = [
    # (local path, auto_compress=False keeps .yaml/.py readable on stage)
    REPO_ROOT / "streamlit" / "semantic_model" / "fsp_marts.yaml",
    REPO_ROOT / "streamlit" / "app" / "streamlit_app.py",
    REPO_ROOT / "streamlit" / "app" / "environment.yml",
]


def snowflake_connect() -> snowflake.connector.SnowflakeConnection:
    load_dotenv(REPO_ROOT / ".env")
    key_path = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]).expanduser()
    pkey = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    pkey_der = pkey.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=pkey_der,
        role="ACCOUNTADMIN",
        warehouse="COMPUTE_WH",
        database="ANALYTICS_DEV",
    )


def main() -> int:
    missing = [p for p in FILES_TO_UPLOAD if not p.exists()]
    if missing:
        print("ERROR: files not found:")
        for p in missing:
            print(f"  {p}")
        return 1

    conn = snowflake_connect()
    cur = conn.cursor()
    print(f"Uploading {len(FILES_TO_UPLOAD)} files to @{STAGE_FQN}")
    for path in FILES_TO_UPLOAD:
        # file://... URIs work cross-platform; forward slashes matter on Windows.
        file_uri = path.as_posix()
        # OVERWRITE=TRUE so reruns are idempotent; AUTO_COMPRESS=FALSE keeps
        # the YAML/Python in their readable form on stage.
        sql = f"PUT 'file://{file_uri}' @{STAGE_FQN} OVERWRITE=TRUE AUTO_COMPRESS=FALSE"
        print(f"  {path.name}")
        cur.execute(sql)
        result = cur.fetchone()
        if result and result[6] != "UPLOADED":
            print(f"    WARN: status={result[6]}")

    print()
    print(f"Stage contents (@{STAGE_FQN}):")
    cur.execute(f"LIST @{STAGE_FQN}")
    for row in cur.fetchall():
        print(f"  {row[0]}  ({row[1]} bytes)")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
