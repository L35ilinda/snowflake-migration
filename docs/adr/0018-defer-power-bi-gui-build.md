# ADR-0018: Defer Power BI GUI build to post-v1.0; v0.3.0-serve declared done at design+scaffold scope

- **Status:** accepted
- **Date:** 2026-04-22
- **Deciders:** Eric Silinda

## Context

`v0.3.0-serve` was scoped as: ADR-0017 design + Snowflake-side identity +
repo walkthroughs + **the actual `.pbix` and `.rdl` GUI builds + screenshots**.

Two scope cuts have already happened on this phase:

1. **Publish to Power BI Service skipped** (ADR-0017 first addendum,
   2026-04-22). `PBI_SVC` Snowflake user destroyed (PR #13). The
   `.pbix` + `.rdl` + screenshots in the repo were positioned as the
   portfolio deliverable.
2. **Now: the `.pbix` and `.rdl` GUI builds themselves are deferred**
   (this ADR, 2026-04-22). Same shape as ADR-0014's deferral of
   Airbyte/queue work — scope-cut for v1.0, deferred to a post-v1.0
   release.

The serving narrative for v1.0 already has Streamlit-in-Snowflake live
(4 tabs over MARTS, ADR-0011 deferral context). Power BI is the
legacy-parity surface, but with both publish AND the GUI build
deferred, the v1.0 Power BI evidence becomes the design artifact:
ADR-0017 + the [power_bi/walkthrough/](../../power_bi/walkthrough/)
docs + the [power_bi/README.md](../../power_bi/README.md) semantic
model spec.

## Decision

**Declare `v0.3.0-serve` done at design+scaffold scope.** The .pbix
and .rdl GUI builds and screenshots move to a parked bullet, deferred
to a post-v1.0 window. No separate `v0.3.0-serve` git tag is created
(precedent: "Replicate Sources declared done at 3-tenant scope" in
ADR-0014 — also no separate tag).

The serving demonstration for v1.0 stands on three legs:
1. **Streamlit-in-Snowflake (live)** — analyst-facing dashboards
   with Cortex Analyst scaffold (region-blocked per ADR-0011).
2. **Power BI design + walkthroughs (in repo)** — proves the SSAS/SSRS
   replacement *plan* is concrete enough to execute, even if execution
   is deferred. Anyone reading [power_bi/README.md](../../power_bi/README.md)
   sees a complete semantic model spec (3 facts, 6 dims, 9
   relationships, 9 DAX measures, hierarchy, cost expectations).
3. **Snowflake side ready** — `BI_WH`, `RM_BI_WH` cap, `FR_ANALYST`
   role; an analyst could connect Power BI Desktop today following
   the walkthroughs and start building.

## Why defer

- **Highest portfolio impact per remaining session is the writeup**
  (v1.0.0). Power BI GUI work is a 2–3 hour exercise that produces
  one .pbix screenshot — incremental over what the design docs and
  Streamlit dashboards already prove.
- **v0.4.0-govern has more SA-role weight per hour:** row access
  policies for multi-tenant isolation is a substantively interesting
  architectural artifact; it tells a stronger story than "I built a
  Power BI .pbix."
- **Time-boxing the v1.0 push.** Three remaining phases (govern,
  orchestrate+AI, writeup) plus the writeup itself — keeping Power BI
  GUI work in v1.0 stretches the timeline without commensurate value.
- **Reversal cost is near zero.** The walkthroughs are tested-by-eye
  step-by-step instructions; whenever the GUI work resumes, it picks
  up against an unchanged Snowflake side.

## Consequences

- **No `v0.3.0-serve` git tag.** Phase 4 status: "declared done at
  design+scaffold scope" — same convention as Replicate Sources at
  3-tenant scope.
- **CLAUDE.md updates:**
  - §4 v0.3.0 Pending → renamed to "Done (Serve declared done at
    design+scaffold scope)"; GUI checkboxes removed and reappear
    under the parked section.
  - §6 Next milestone → rewritten to target v0.4.0-govern.
  - §9 phase 4 → reflects design+scaffold scope; GUI work moved to
    parked bullet.
  - §8 deferred questions → no changes.
- **ADR-0017 gets a second addendum at the top** noting the GUI
  deferral, parallel to the publish-skip addendum. ADR-0017's §1 +
  §2 design decisions remain canonical for whenever the GUI work
  resumes.
- **`power_bi/` directory stays in the repo** — design + walkthroughs
  + empty `screenshots/` placeholder. No deletions.
- **Snowflake state unchanged** — `PBI_SVC` was already destroyed via
  PR #13; nothing else needs touching.
- **Roadmap %** to v1.0.0 jumps from ~57% to ~63% with this scope cut
  (Phase 4 reweights from 40% complete to 100% complete at scope).
- **Parked bullet (post-v1.0):** GUI build of `fsp_marts.pbix`
  (DirectQuery) + `fsp_advisor_commissions.rdl` (Import) + screenshots
  + tag. Walkthroughs in the repo are the canonical instructions.

## Reversal triggers

Promote the GUI build back into v1.0 if any of:

- The portfolio writeup rehearsal exposes "no live Power BI artifact"
  as a weak SA story (low likelihood — the design docs + Streamlit
  serving cover the substantive demonstration).
- A reviewer specifically asks for the .pbix file (also low — the
  walkthroughs are reviewable as design artifacts).
- A real consulting engagement adopts the project as a baseline and
  needs the .pbix to hand to a stakeholder.