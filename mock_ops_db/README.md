# mock_ops_db

Mock operational database for the Replicate Sources phase. Stands in for the
legacy SQL Server operational systems being replaced. Self-hosted Airbyte
(Phase B) replicates from this Postgres into `ANALYTICS_DEV.RAW_OPS` in
Snowflake. See [ADR-0013](../docs/adr/0013-airbyte-self-hosted-for-mock-ops-db.md).

## Schema

Two tables under the `ops` schema:

| Table | Rows (seeded) | Purpose |
|---|---|---|
| `ops.policies_master` | 10,000 | Master policy records (active + lapsed) |
| `ops.claims` | 3,000 | Claim events against policies |

Both tables have `created_at`, `updated_at` (trigger-managed), and
`is_deleted` columns to support Airbyte CDC mode in Phase B. Full schema in
[seed/01_schema.sql](seed/01_schema.sql).

## Stand it up locally

```bash
cd mock_ops_db
cp .env.example .env       # adjust password if you like; default is fine for local
docker compose up -d
```

First boot runs `seed/01_schema.sql` then `seed/02_seed.sql`. ~10K rows in
`policies_master`, 3K in `claims`. Reseeding requires a volume wipe:

```bash
docker compose down -v && docker compose up -d
```

## Verify

```bash
docker exec -it mock_ops_postgres psql -U ops_admin -d ops -c "select count(*) from ops.policies_master;"
docker exec -it mock_ops_postgres psql -U ops_admin -d ops -c "select count(*) from ops.claims;"
```

## Next: stand up Airbyte (Phase B)

Not done yet. The Snowflake side is Terraform-managed (`RAW_OPS` schema,
`AIRBYTE_SVC` user, `FR_AIRBYTE` role). Phase B steps:

1. Generate the AIRBYTE_SVC key pair:
   ```powershell
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out C:\Users\Lonwabo_Eric\.snowflake\keys\airbyte_svc_rsa_key.p8 -nocrypt
   openssl rsa -in C:\Users\Lonwabo_Eric\.snowflake\keys\airbyte_svc_rsa_key.p8 -pubout -out C:\Users\Lonwabo_Eric\.snowflake\keys\airbyte_svc_rsa_key.pub
   ```
   Strip the PEM headers from the `.pub` before letting Terraform read it
   (same convention as `ci_svc_rsa_key.pub`).
2. `terraform apply` the Snowflake side.
3. Install Airbyte locally: `abctl local install` (recommended) or the
   Docker quickstart.
4. In the Airbyte UI:
   - **Source:** Postgres → host `host.docker.internal`, port `5432`, db `ops`,
     user `ops_admin`, password from `.env`. Choose `Standard` replication
     mode for first sync.
   - **Destination:** Snowflake → account `VNCENFN-XF07416`, db `ANALYTICS_DEV`,
     schema `RAW_OPS`, user `AIRBYTE_SVC`, key-pair auth (paste contents of
     `airbyte_svc_rsa_key.p8`).
   - **Connection:** sync both `policies_master` and `claims`, every 24h.
5. Run the sync; verify rows land in `ANALYTICS_DEV.RAW_OPS.POLICIES_MASTER`
   and `…CLAIMS`.
6. Add dbt staging models in `dbt/models/staging/ops/`.
7. Upgrade source mode to `Logical Replication (CDC)`.
