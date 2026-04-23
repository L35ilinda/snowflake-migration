# Session protocol — non-negotiable

This document defines how every working session on this project is captured.
It is **mandatory**, not aspirational. Plans, decisions, and execution
chronology live in the repo — not in chat history. If a decision or its
rationale isn't written down here, it didn't happen.

> Audience: anyone — human or AI assistant — picking up work on this
> project. Reading this file should be enough to onboard cold.

## Why this protocol exists

ADRs answer "why did we pick X." Git history answers "what changed."
[CLAUDE.md](../CLAUDE.md) answers "what is the current state." None of
them answer:

- *What did we plan to do this morning?*
- *How did the plan evolve during execution?*
- *What did we actually do, step by step?*
- *Which gotchas cost time?*

Without a session-tracking discipline, any reasoning that lives only in
chat (alternatives ruled out, scope flags considered, won't-do items)
is lost the moment the conversation ends. The next person — or the
same person three weeks later, or an AI assistant in a fresh
conversation — has to re-derive everything from scratch.

This protocol prevents that.

## The five-document system

| Document | Holds |
|---|---|
| [`CLAUDE.md`](../CLAUDE.md) | Current project state (§4) + roadmap (§9) + active open questions (§8). The "what / where" snapshot. |
| [`docs/adr/NNNN-<slug>.md`](adr/) | Decision records. One ADR per non-trivial choice. Captures options + the why. |
| [`docs/log/YYYY-MM-DD.md`](log/) | Daily session log. Plan + execution + shipped + issues for that day. |
| [`docs/log/issues-and-fixes.md`](log/issues-and-fixes.md) | De-duplicated catalogue of gotchas. Anything >15 min to debug lands here. |
| Memory (assistant-side) | Cross-session preferences. Pointers to the above; never the primary source of truth. |

Every session touches the daily log file. Most touch CLAUDE.md or an
ADR. Issues-and-fixes is touched as gotchas surface.

## The daily log template

Canonical template lives in [`log/README.md`](log/README.md). Every
daily file (`docs/log/YYYY-MM-DD.md`) has these **seven sections in
this exact order**:

```
# YYYY-MM-DD — <one-line session focus>

## Roadmap context (start of session)
## Session plan
## ADRs created or updated
## Shipped + test plan
## Issues and fixes encountered
## Session log
## Open checkboxes — what's next
```

### What goes in each section

**1. Roadmap context (start of session)** — written first, before anything else.
- Current phase + status (e.g. "v0.3.0-serve declared done at scope; v0.4.0-govern starting")
- Tag history pointer (last shipped tag + commit SHA)
- % to v1.0.0 (rough estimate)
- Active blockers / parked items relevant to the session

**2. Session plan** — written second, **before any code is touched**.
- Order of work (numbered steps)
- Options considered, with the choice and the why
- Won't-do list (scope flags — what we're explicitly not doing)
- Risk flags (what could go wrong)
- Test plan per item (where useful)
- ADR(s) anticipated

The plan **may evolve** mid-session. When it does, **strike through or
mark "(revised)"** — do not delete the original. The diff is the
value: it shows how the plan adapted to reality.

**3. ADRs created or updated** — every ADR touched gets a row.
- New ADRs: title + link
- Updated ADRs: what changed (status banner, addendum, addition)

**4. Shipped + test plan** — every PR that merges gets a row.

| PR | Title | Merge | Tag | Test plan |
|---|---|---|---|---|

Includes CI status, dbt test pass/fail counts, manual verification
spot-checks. **No PR ships without a row here.**

**5. Issues and fixes encountered** — gotchas that surfaced.
- Anything >15 min to debug: promote to
  [`issues-and-fixes.md`](log/issues-and-fixes.md) under the right
  section, then back-link from this section.
- Trivial gotchas (one-off typos, expected warnings) can stay inline
  here — don't pollute the catalogue.

**6. Session log** — chronological narrative diary.
- Free-form. Checkbox lines for completed steps; prose for context.
- Links to file paths, commits, ADRs as references.
- This is the human-readable "what actually happened" timeline.

**7. Open checkboxes — what's next** — end-of-session handoff.
- Mirrors the live in-flight task list at session end.
- Becomes input to the **next** day's "Roadmap context" section.
- Carries unfinished items + parked items + new follow-ups discovered during the session.

## Timing — what gets written when

| Section | Captured when |
|---|---|
| Roadmap context | First action of the session, before any code |
| Session plan | Second action, before any code; show plan to user, get confirmation |
| ADRs created/updated | As each ADR is written (real-time) |
| Shipped + test plan | After each PR merges, with merge SHA + CI status |
| Issues and fixes | When a >15 min gotcha hits (real-time, before fixing) |
| Session log | Real-time, as work happens |
| Open checkboxes | End of session, mirrors live task list |

## Non-negotiable rules

1. **No code before plan.** If a non-trivial change is starting and
   there's no Session plan section yet, write it first. Show it to
   the user (or yourself, if working solo). Get confirmation if
   collaborating.

2. **Every PR has a Shipped row.** Number, title, merge SHA, tag (if
   any), CI status. No exceptions, even for tiny doc-only PRs.

3. **Every ADR gets a row in "ADRs created or updated."** Brand new
   ADRs and updates (banners, addenda) both count. The row must say
   what kind of touch it was.

4. **Plans evolve via diff, not deletion.** If a planned approach
   changes mid-session, strike through with `~~text~~` or note
   "(revised)" — don't delete the original. Git diff captures the
   evolution; deletion erases it.

5. **Issues >15 min get promoted to issues-and-fixes.md.** Inline
   notes are fine for trivial gotchas; durable lessons live in the
   catalogue under the right `## <Category>` section.

6. **End-of-session: pass the baton.** The "Open checkboxes" section
   MUST mirror the live in-flight task list. The next session's
   "Roadmap context" reads from this. Failing to fill this in breaks
   the next session's startup.

7. **CLAUDE.md drift is technical debt.** When code changes
   meaningfully change project state, update CLAUDE.md §4 (Done /
   Pending / state) in the **same PR** as the change, not the next
   one. See CLAUDE.md operating rules.

8. **Older logs are not retrofitted.** Anything pre-dating
   2026-04-23 is a flat narrative without the seven-section split.
   Reconstructing pre-execution plans for past sessions is
   best-effort fiction. Apply the template forward only.

## Workflow loop (one session, end to end)

```
1. Read CLAUDE.md §4 (Done / Pending / state) and §6 (Next milestone).
2. Read previous day's "Open checkboxes — what's next."
3. Create today's docs/log/YYYY-MM-DD.md from the template.
4. Fill in "Roadmap context (start of session)."
5. Fill in "Session plan." Show to user. Get confirmation if needed.
6. Execute. As you go:
     - Real-time: append to "Session log"
     - When an ADR is written: add row to "ADRs created or updated"
     - When a >15-min gotcha hits: promote to issues-and-fixes.md, back-link here
     - When a PR merges: add row to "Shipped + test plan"
7. Update CLAUDE.md §4 / §6 / §9 / §8 as state changes (in the same
   PRs as the changes themselves).
8. End of session: fill in "Open checkboxes — what's next."
9. Commit any uncommitted doc changes as a tiny housekeeping PR.
```

## Failure modes to watch for

- **"I'll just remember this."** No, you won't. Two weeks later the
  detail is gone. Write it down.
- **"It's a small change, no plan needed."** If it's small, the plan
  section is small. Still write it. The discipline is the value.
- **"I'll update CLAUDE.md later."** "Later" turns into "never." Ship
  it in the same PR as the change.
- **Plans that disappear when the work changes.** Strike-through, don't
  delete. The diff is the lesson.
- **Skipping the daily file because nothing big shipped.** Even a
  research-only or docs-only session deserves a log. Future-you needs
  to know what was attempted, not just what shipped.
- **Writing the plan after execution** ("retro-planning"). Defeats the
  purpose. The plan is valuable because it's *pre*-decision. If you
  forgot, write a brief retro entry honestly: "Plan section: not
  captured at session start — see Session log for what actually
  happened."

## Concrete example to study

[`docs/log/2026-04-24.md`](log/2026-04-24.md) — first file written
natively in this template. Shows the full protocol applied: roadmap
context populated from the previous day's open checkboxes; session
plan captured pre-execution with options, won't-do, risk flags, ADRs
anticipated; remaining sections start empty and fill in as work
happens.

[`docs/log/2026-04-23.md`](log/2026-04-23.md) — first file
retrofitted to the template. Shows how an existing flat narrative was
reorganised; useful for understanding the section semantics by example.

## Teaching argument (one paragraph)

A repository's `git log` tells you what changed and when. Its ADRs
tell you why decisions were made. Its README tells you what it does.
None of them tell you what was being attempted in the moment, what
options were on the table, what almost shipped but didn't, what cost
hours to debug. That story — the one that distinguishes a portfolio
project that demonstrates judgement from one that just demonstrates
output — lives in the daily session log, written under this protocol.
The discipline is the demonstration.
