# ADR-0012: Snowpipe quarantine — shared table populated by VALIDATE_PIPE_LOAD task

- **Status:** accepted
- **Date:** 2026-04-21
- **Deciders:** Eric Silinda

## Context

Every Snowpipe in this project runs with `ON_ERROR = CONTINUE`. That keeps a
pipe healthy when source data is malformed (missing columns, bad date format,
unparseable numbers, encoding glitches), but the rejected rows are silently
dropped. There is no record of what failed unless someone is watching pipe
load history at the moment of failure.

This is fine for synthetic-data demos. It is unacceptable for the enterprise
narrative the project is building toward — at production scale "we lost some
rows yesterday and don't know which" is the wrong answer.

`COPY INTO` in non-pipe contexts supports `VALIDATION_MODE` to inspect rejects
before loading. Snowpipe does not — but Snowflake exposes `VALIDATE_PIPE_LOAD()`,
a table function that returns the errors from any pipe's load history within
the last 14 days. This ADR picks how to wire it in.

## Options considered

1. **Per-pipe quarantine tables.** One `<pipe>_errors` table per Snowpipe, each
   populated by its own task. Pros: blast-radius isolation; obvious lineage.
   Cons: 18 tables today, more as the queue is onboarded; querying "today's
   failures across all sources" requires an 18-way UNION; 18 tasks instead of 1.

2. **One shared quarantine table populated by one task using `VALIDATE_PIPE_LOAD()`.**
   Single `pipe_errors` table with a `pipe_name` column; one task UNION-ALLs
   `VALIDATE_PIPE_LOAD()` over every pipe FQN every 5 min and MERGEs into the
   table. Pros: 1 table + 1 task; cross-source triage is `WHERE pipe_name = …`;
   storage is single-sourced. Cons: one task touching all pipes; if it fails
   silently you lose visibility for everything (mitigated by `SYSTEM$TASK_HISTORY`).

3. **Stream + task on landing tables.** Use a Snowflake Stream on each landing
   table to detect new rows, then a task to compare against the source file.
   Doesn't work — `ON_ERROR = CONTINUE` discards rejects entirely; they never
   land in the table, so no stream sees them.

4. **Stored procedure that introspects `INFORMATION_SCHEMA.PIPES`.** A single
   procedure loops over all pipes dynamically, no Terraform change needed when
   pipes are added. Pros: zero-touch as the project grows. Cons: stored proc
   ownership and grants add complexity; stringly-typed dynamic SQL is hard to
   review; debugging cursors in Snowflake is unpleasant. Marginal upside today
   given pipe FQNs are already known to Terraform.

5. **Event-driven dead-letter on Azure Event Grid.** Configure DLQ on the Event
   Grid subscription so failed deliveries land in a separate blob container.
   Pros: catches Event-Grid-side delivery failures (which `VALIDATE_PIPE_LOAD`
   does not). Cons: a different problem — captures *delivery* failures, not
   *parse* failures; the latter is the actual pain point. Worth adding later
   alongside option 2, not as a replacement.

## Decision

Chose **option 2** — one shared table, one task. New module `snowflake_quarantine`
encapsulates schema dependency, table DDL, and task body. Wired into
`environments/dev/main.tf` with all 18 current pipe FQNs.

Primary reason: this matches the project's "minimal complexity at this scale"
precedent (ADR-0009 chose shared CI schemas over per-PR for the same reason).
A team of one running synthetic data does not benefit from per-pipe isolation;
it benefits from one query across everything.

If pipe count grows past ~50 or if individual tenants need their own retention
policies, revisit and split per tenant — not per pipe.

## Consequences

- **New schema:** `RAW_QUARANTINE` in `ANALYTICS_DEV`. Created in
  `environments/dev/main.tf` (not in `database_layers`), kept separate from
  per-tenant `RAW_*` schemas because it spans tenants.
- **New table:** `RAW_QUARANTINE.PIPE_ERRORS` with all 13 columns from
  `VALIDATE_PIPE_LOAD()` plus `pipe_name` and `captured_at`. `CHARACTER` is
  renamed to `CHARACTER_POS` to dodge the reserved word.
- **New task:** `RAW_QUARANTINE.TSK_CAPTURE_PIPE_ERRORS` running on `LOAD_WH`,
  scheduled every 5 minutes. Owner-mode (runs as ACCOUNTADMIN, the role that
  applied Terraform). Started on apply.
- **Dedup:** task body is `MERGE` keyed on
  `(pipe_name, file_name, row_number, line)` so the 10-minute lookback window
  doesn't double-write. `COALESCE` on each key handles nulls (some error
  categories don't populate `row_number`).
- **RBAC:** schema added to `module.rbac` with RW for `FR_ENGINEER`, RO for
  `FR_ANALYST`. Analysts can see what failed but cannot mutate the audit log.
- **Cost:** ≈ 0.1 credit/month on `LOAD_WH`. Already inside `RM_LOAD_WH`'s
  5-credit cap. Negligible.
- **Pipe FQN list is hardcoded** in `environments/dev/main.tf`. Each new pipe
  added to the project must also be appended to that list. Acceptable friction
  given the alternative (option 4) trades it for stored-proc complexity.

## Known limitations

- **No alerting.** Errors accumulate silently. A follow-up Snowflake Alert on
  `pipe_errors` row-count delta would close this loop. Out of scope here.
- **No DLQ on Event Grid.** Captures parse failures, not delivery failures.
  See ADR-0010 known limitations.
- **14-day VALIDATE_PIPE_LOAD horizon.** If the task is paused for more than
  14 days, older errors are unrecoverable.
- **MERGE key has edge cases.** Two distinct errors on the same `(pipe, file,
  row, line)` collapse to one row. In practice each rejected row produces one
  error; if Snowflake ever changes that, the dedup needs revisiting.
