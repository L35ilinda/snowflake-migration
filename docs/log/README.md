# Action log

Chronological record of work done on this project. Narrative complement to the
ADRs in [../adr/](../adr/) and the state summary in
[../../CLAUDE.md](../../CLAUDE.md) §4.

> **Protocol governing this directory:** [../SESSION_PROTOCOL.md](../SESSION_PROTOCOL.md).
> The protocol is **non-negotiable** and the canonical reference for
> when / what / how to capture a session. The template below is a
> reproducible artifact of the protocol; the protocol is the
> source of truth.

## Start here if you are replicating the project

[**issues-and-fixes.md**](issues-and-fixes.md) — de-duplicated catalogue of
every non-trivial blocker we hit, with root cause, fix, and replication tip.
If you are rebuilding from zero, read that first. The daily files below are
chronology; the issues file is the lookup table.

## How this log is structured

- **One file per working day**, named `YYYY-MM-DD.md` (SAST timezone).
- **Append-only within a day.** Never edit a historical day after closing
  it — add today's correction on today's file.
- Each daily file follows the **template below**. The "Session plan"
  section is captured **before execution**; the rest fills in as the day
  progresses.
- Decisions link to ADRs; implementation steps link to commit SHAs / PR
  numbers as commits flow.

## Daily file template

```markdown
# YYYY-MM-DD — <one-line session focus>

## Roadmap context

Where we are at the start of this session. Brief.
- Current phase + status (e.g. "v0.3.0-serve declared done at scope; v0.4.0-govern starting")
- Tag history pointer (link to CLAUDE.md §9 if useful)
- % to v1.0.0 (rough estimate)
- Active blockers / parked items relevant to the session

## Session plan

Pre-execution plan. Captured BEFORE any code is written.
- Order of work
- Options considered (with the choice and the why)
- Won't-do list (scope flags)
- Risk flags
- Test plan (per item where useful)
- ADR(s) anticipated

This section may get edited mid-session as the plan firms up — git diff
preserves the evolution. Do not delete superseded items; strike them
through or add a "(revised)" note.

## ADRs created or updated

- ADR-XXXX (new) — title, link
- ADR-YYYY (updated) — what changed (banner / addendum / addition)

## Shipped + test plan

What landed today. Each item:
- PR number + merge commit SHA
- Tag if any
- One-line summary
- Test plan + verification result (PASS=N, WARN=N, ERROR=N for dbt; CI status; spot-check queries)

## Issues and fixes encountered

Cross-references to issues-and-fixes.md additions, OR brief inline notes
if minor and not worth promoting to the catalogue. New gotchas that
took >15 min to debug should land in issues-and-fixes.md with a back-link
here.

## Session log

Chronological narrative of what actually happened. The detail.
Free-form — checkbox lines for completed steps, prose for context, links
to file paths / commits / ADRs as references. This is the diary.

## Open checkboxes — what's next

Pulls in-flight work that carries forward. Mirrors the live TodoWrite
list at end of session. Becomes input to the next day's "Session plan."
```

## Why this exists

Git history captures *what changed*. CLAUDE.md §4 captures *current state*.
ADRs capture *why we picked X*. PR bodies capture *what shipped*. None of
them answer the questions:

- *What did we plan to do this morning, and how did the plan evolve?*
- *What did we actually do last Tuesday, step by step?*
- *Which gotchas cost time?*

This log fills those gaps. The "Session plan" section in particular is
what's visible *before* an ADR exists or a PR is opened — the reasoning
that's otherwise locked in chat history and lost.

## Convention notes

- **Older logs (2026-04-15 → 2026-04-22)** predate this template.
  They are flat narratives without the section split. Do not retrofit
  them; the chronology is intact and reconstructing the pre-execution
  plans for past sessions is best-effort fiction.
- **2026-04-23.md** is the first file retrofitted to the new template
  (also serves as a lived example).
- **2026-04-24.md onward** uses the template natively.
