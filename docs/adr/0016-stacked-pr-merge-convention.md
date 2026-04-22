# ADR-0016: Stacked PR merge convention for branch-protected master

- **Status:** accepted
- **Date:** 2026-04-22
- **Deciders:** Eric Silinda

## Context

Branch protection on `master` requires PRs (no direct pushes). When two
commits depend on each other and both should land in the same release,
the natural pattern is **stacked PRs**:

```
master
   |
   +— PR-A (base: master, head: branch-A, contains commit-1)
       |
       +— PR-B (base: branch-A, head: branch-B, contains commit-2)
```

PR-B is "stacked on" PR-A — its diff shows only commit-2 because PR-A
covers commit-1.

This was used to land v0.2.0-model-the-warehouse:
- PR #9 — Replicate Sources finalisation (`replicate-sources/finalisation` → `master`)
- PR #10 — v0.2.0 model-the-warehouse (`core/vault-and-type2` → `replicate-sources/finalisation`)

When PR #9 was merged with `gh pr merge --merge --delete-branch`,
PR #10 was **auto-closed** by GitHub because its base branch
(`replicate-sources/finalisation`) ceased to exist. GitHub does not
auto-retarget closed-because-base-deleted PRs to the default branch.

A new PR (#11) had to be opened from the same head branch
(`core/vault-and-type2`) targeting `master`. The original PR thread
(#10) is permanently closed and unrecoverable.

## Decision

**Retarget downstream stacked PRs to `master` before deleting the
upstream branch.**

Concrete merge sequence for stacked PRs going forward:

```bash
# 1. Merge upstream PR — but do NOT pass --delete-branch yet.
gh pr merge <upstream-pr> --merge

# 2. Retarget every PR currently based on the upstream branch.
gh pr edit <downstream-pr> --base master

# 3. Now the upstream branch is unreferenced — safe to delete.
git push origin --delete <upstream-branch>
# (or via the GitHub UI / gh api if preferred)

# 4. Watch CI on the retargeted downstream PR; merge when green.
gh pr checks <downstream-pr> --watch
gh pr merge <downstream-pr> --merge --delete-branch
```

## Why not the alternatives

- **Open both PRs against `master` from day one** (no stacking). Works
  but the second PR's diff is noisy (shows commit-1 changes too) until
  PR-A merges. Acceptable for two-commit stacks; gets unreadable for
  three-or-more.
- **Use `--auto` merge with stacked PRs.** GitHub's auto-merge does not
  rebase or retarget downstream PRs — same auto-close blast radius as
  the manual case. Doesn't help here.
- **Delete the base branch via the GitHub UI before merging.** Same
  result — UI deletion auto-closes dependent PRs identically.
- **Stacked PR tools (`spr`, Graphite, `git-stacked`).** Right answer
  for repos with frequent stacked work. Overkill for a portfolio
  project that stacks ~once per release.

## Consequences

- **Operational checklist** added to merge-time muscle memory: retarget
  before delete. The four-line `gh` sequence above is the canonical
  recipe.
- **Cross-referenced** in [issues-and-fixes.md](../log/issues-and-fixes.md)
  under a new "GitHub workflow" section so anyone replicating the project
  hits the recipe without needing to read this ADR.
- **No tooling adoption.** Stacked-PR tools deferred until stack depth
  or frequency justifies the dependency.
- **Closed PR #10** stays closed in the repo's history as evidence of
  the lesson; PR #11 references it explicitly in its body.
