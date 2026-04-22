# 04 — Publish with PBI_SVC service identity

Optional for the portfolio — the .pbix and .rdl in the repo plus the
screenshots already tell the story. Walk this only if you have a Power
BI Pro license and want a live workspace URL.

## What changes from build phase

| Aspect | Build (steps 01–03) | Publish (this step) |
|---|---|---|
| Snowflake user | `LSILINDA` | `PBI_SVC` |
| Snowflake auth | OAuth (browser SSO) or password | **Key-pair** |
| Where credentials live | Local Power BI Desktop | Power BI Service "cloud connection" |
| Schedule | Manual refresh | Optional refresh schedule (Import only — DirectQuery is live) |

`PBI_SVC` is already provisioned with key-pair auth (Terraform applied
2026-04-22). Public key registered on the Snowflake user; private key at
`C:/Users/Lonwabo_Eric/.snowflake/keys/pbi_svc_rsa_key.p8`.

## Steps

### 1. Publish the semantic model

In Power BI Desktop:
- **Home → Publish**.
- Sign in to Power BI Service.
- Choose **My workspace** (free) or a Power BI Pro workspace (paid).
- Wait for upload.

### 2. Configure the cloud connection for `PBI_SVC`

In Power BI Service (https://app.powerbi.com):

1. **Settings (cog icon, top right) → Manage connections and gateways → New**.
2. **Connection type:** Snowflake.
3. **Server:** `vncenfn-xf07416.snowflakecomputing.com`
4. **Warehouse:** `BI_WH`
5. **Authentication method:** **Key Pair**.
6. **Username:** `PBI_SVC`.
7. **Private key:** paste the full contents of
   `C:/Users/Lonwabo_Eric/.snowflake/keys/pbi_svc_rsa_key.p8`
   (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`
   lines).
8. **Privacy level:** Organizational.
9. **Create**.

### 3. Bind the dataset to the new connection

1. In your workspace, find the published `fsp_marts` dataset.
2. **Settings → Data source credentials → Edit credentials**.
3. **Authentication method:** OAuth2 → switch to the new key-pair
   connection.
4. **Sign in / Apply**.

### 4. Publish the paginated report

Power BI Report Builder:
- **File → Publish → Power BI service**.
- Same workspace.
- The published .rdl uses the same dataset connection — re-bind via
  Settings if it picked up the LSILINDA build-time creds.

### 5. Verify

In Power BI Service:
- Open the published `fsp_marts` report → all visuals should render
  using `PBI_SVC` (check the Snowflake QUERY_HISTORY view —
  `select user_name, count(*) from snowflake.account_usage.query_history where user_name = 'PBI_SVC' and start_time > dateadd('hour', -1, current_timestamp()) group by 1`).
- Open the published paginated report → render with parameters →
  same `PBI_SVC` queries appear in the Snowflake history.

## Common failures

- **"Token expired"** on first DirectQuery interaction — Power BI
  refreshed the cloud connection; just retry the visual.
- **"Authentication failed"** with the key-pair connection — most
  often the private key was pasted with extra whitespace at the
  end of the BEGIN/END lines. Re-paste cleanly.
- **`PBI_SVC` shows up in Snowflake login history but every query
  fails with "object does not exist"** — `default_role` not applied.
  Verify with `desc user PBI_SVC` → `default_role` should be
  `FR_ANALYST`. If wrong, run
  `alter user PBI_SVC set default_role = 'FR_ANALYST'`.

## Cost flag

Once published with DirectQuery, every interactive user click hits
`BI_WH`. With auto-suspend 60s and resume cost ~3-5s per cold query,
expect 5-10 credits/month at typical use. **`RM_BI_WH` caps at 2
credits/month** — the cap will trip under any sustained demo. That's
the FinOps demonstration; let the cap trip and screenshot the
suspension event for the portfolio writeup.

## Done

When you have screenshots of the model + paginated report rendering
against Snowflake, that's `v0.3.0-serve` complete. Tag accordingly.
