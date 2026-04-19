# ADR-0010: Snowpipe auto-ingest via Azure Event Grid

- **Status:** accepted
- **Date:** 2026-04-19
- **Deciders:** Eric Silinda

## Context

With RAW, STAGING, CORE, and MARTS in place, the Snowpipe layer still required manual `ALTER PIPE ... REFRESH` to pick up new files. This defeats the continuous-ingestion narrative that sets Snowpipe apart from legacy batch ETL.

Azure supports Snowpipe auto-ingest via:

```
File lands in blob container
  → Event Grid System Topic fires BlobCreated event
  → Event Subscription (filtered by prefix/suffix) routes to Storage Queue
  → Snowflake Notification Integration polls the Queue
  → Snowpipe (AUTO_INGEST = TRUE, INTEGRATION = <ni>) fires COPY INTO
```

Latency target: 30-60 seconds from file arrival to row visibility.

## Decisions

### One shared notification integration and one shared queue

Same pattern as the shared `SI_AZURE_FSPSFTPSOURCE_DEV` storage integration (ADR-0003). A single `NI_AZURE_FSPSFTPSOURCE_DEV` notification integration and a single `snowpipe-events` storage queue cover every company container. Per-pipe filtering happens via Snowpipe's own `PATTERN` regex once the notification is delivered, and at the Event Grid subscription level via `subject_begins_with = /blobServices/default/containers/fsp-` and `subject_ends_with = .csv`.

Rejected: one queue per company. Would add N subscription resources and N notification integrations for no real isolation gain — we already scope per-tenant at the stage and RBAC layers.

### Create an Event Grid System Topic explicitly, not via data source

Initial assumption: Azure auto-provisions a system topic on every storage account. Wrong — system topics must be explicitly created (scoped to `source_arm_resource_id` of the storage account). Corrected in the module. One system topic per storage account is the recommended pattern.

### Two-step apply bootstrap

On first apply, Snowflake fails to create pipes because it cannot reach the queue yet — consent and RBAC must land in between. Accepted workflow:

1. `terraform apply` — creates queue, system topic, subscription, notification integration. Pipe creation fails with `Pipe Notifications bind failure: could not locate queue`.
2. Run `DESC NOTIFICATION INTEGRATION NI_AZURE_FSPSFTPSOURCE_DEV` to grab `AZURE_CONSENT_URL` and `AZURE_MULTI_TENANT_APP_NAME`. (The `snowflakedb/snowflake` v1.x provider does not expose these as resource attributes, unlike for storage integrations.)
3. Admin-consent the Snowflake enterprise app — equivalent to `az ad sp create --id <client-id>`.
4. Grant `Storage Queue Data Contributor` on the storage account scope to the service principal.
5. `terraform apply` again — pipes create successfully.

Rejected: a single hands-off apply. Azure AD admin consent is an external prerequisite that cannot be scripted end-to-end in Terraform without circular dependency. Accepting the two-step pattern is the same trade-off as ADR-0003.

### Reuse `TRANSFORM_WH` — no separate Snowpipe warehouse

Snowpipe uses Snowflake-managed serverless compute, not a customer warehouse. The `TRANSFORM_WH` stays dedicated to dbt. A separate `LOAD_WH` exists but is only for manual `COPY INTO` work or scheduled tasks — not for Snowpipe itself.

### AUTO_INGEST behaviour is a ForceNew pipe attribute

Toggling `auto_ingest` on existing pipes forces replacement (Snowflake API limitation — `ALTER PIPE` cannot change this). All 18 pipes were replaced when this ADR was applied. Harmless — pipes have no state and were recreated in the same apply.

## Consequences

- **No more manual refresh.** Files dropped in `fsp-main-book/`, `fsp-indigo-insurance/`, `fsp-horizon-assurance/` trigger their matching pipes automatically.
- **Verified latency: 41 seconds** in the first end-to-end test (file uploaded → row visible in `RAW_MAIN_BOOK.MAIN_BOOK_VALUATIONS`).
- **New Azure resources in state:** one Event Grid System Topic (`fspsftpsource-system-topic`), one Event Subscription (`ni-azure-fspsftpsource-dev-blob-created`), one Storage Queue (`snowpipe-events`).
- **New Snowflake resource:** `NI_AZURE_FSPSFTPSOURCE_DEV` notification integration.
- **New role assignment:** `Storage Queue Data Contributor` on `fspsftpsource` storage account to Snowflake's multi-tenant service principal.
- **Pipes `AUTO_INGEST = TRUE`, `INTEGRATION = NI_AZURE_FSPSFTPSOURCE_DEV`.** `ON_ERROR = CONTINUE` unchanged.
- **Snowpipe cost** is per-file loaded (not per warehouse credit). For our scale, negligible. Worth noting in the portfolio writeup as a cost-shape distinction from scheduled `COPY INTO`.

## Known limitations to revisit

- `_LOADED_AT` column default (`CURRENT_TIMESTAMP()`) does not fire on `COPY INTO` — rows land with `NULL` in that column. Fix is to either change the column to a `MERGE` assigned value via the pipe's `COPY INTO` clause (`SELECT $1, $2, ..., CURRENT_TIMESTAMP()`) or drop the column as misleading. Defer for now.
- No dead-letter queue for events that fail routing. Event Grid supports DLQ to a separate blob container; add if needed.
- No Snowflake alerting on pipe errors. `SYSTEM$PIPE_STATUS` must be polled manually. Could wire up a Snowflake Alert + notification integration later.
- Bootstrap is two-step. Documented in module README.
