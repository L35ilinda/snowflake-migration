# Action log

Chronological record of work done on this project. Narrative complement to the ADRs in [../adr/](../adr/) and the state summary in [../../CLAUDE.md](../../CLAUDE.md) §4.

## Start here if you are replicating the project

[**issues-and-fixes.md**](issues-and-fixes.md) — de-duplicated catalogue of every non-trivial blocker we hit, with root cause, fix, and replication tip. If you are rebuilding from zero, read that first. The daily files below are chronology; the issues file is the lookup table.

## How this log is structured

- **One file per working day**, named `YYYY-MM-DD.md` (SAST timezone).
- **Append-only within a day.** Never edit a historical day after closing it — add today's correction on today's file.
- Each entry is a completed-checkbox line with one clause of context — the same shape as TodoWrite items, but persisted.
- Decisions link to ADRs; implementation steps link to commit SHAs once commits start flowing.
- Open checkboxes at the bottom of the latest file mirror the in-flight TodoWrite list — "what's next."

## Why this exists

Git history captures *what changed*. CLAUDE.md §4 captures *current state*. ADRs capture *why we picked X*. None of them answer the question "what did we actually do last Tuesday, step by step?" — which is the story you tell in an interview or portfolio writeup. This log fills that gap.
