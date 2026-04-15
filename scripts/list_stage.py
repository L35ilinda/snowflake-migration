import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from cryptography.hazmat.primitives import serialization
import snowflake.connector

load_dotenv()

key_path = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]).expanduser()
passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
pkey = serialization.load_pem_private_key(
    key_path.read_bytes(),
    password=passphrase.encode() if passphrase else None,
)
pkey_der = pkey.private_bytes(
    encoding=serialization.Encoding.DER,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    private_key=pkey_der,
    role=os.environ["SNOWFLAKE_ROLE"],
    warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    database=os.environ.get("SNOWFLAKE_DATABASE", "ANALYTICS_DEV"),
)

try:
    cur = conn.cursor()
    cur.execute("LIST @ANALYTICS_DEV.RAW_MAIN_BOOK.STG_COMPANY_01_OUTBOUND/Outbound;")
    rows = cur.fetchall()
    print(f"Files found: {len(rows)}")
    for r in rows[:10]:
        print(r[0], r[1])
    if len(rows) > 10:
        print(f"... ({len(rows) - 10} more)")
finally:
    conn.close()
