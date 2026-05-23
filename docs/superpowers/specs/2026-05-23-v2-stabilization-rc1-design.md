# v2.0.0-rc1 Stabilization Release — Design

**Date:** 2026-05-23
**Status:** Approved
**Scope:** Post-merge stabilization fixes → nightly CI validation → tag `v2.0.0-rc1`
**Out of scope:** Galaxy publish, sharding modernization (sub-project 2), backup feature (sub-project 3)

## Context

PR #1 (v2.0.0 foundation refactor) merged into `origin/main` on 2026-05-23. Local `main` is stale at `56a32bc` — requires `git pull --ff-only` before branching. A final code review surfaced 7 findings post-merge, plus a temporary debug commit (`649b4c7`) that leaked into main. Three nightly molecule scenarios exist but have never executed in CI.

## Approach

Single branch `fix/v2-stabilization` off updated `main`. All fixes land in one PR with per-finding commits. Nightly scenarios are triggered via `workflow_dispatch` from the branch after the critical runtime bug is fixed, running in parallel with remaining cleanup tasks. Merge after all conditions met → annotated tag `v2.0.0-rc1` → GitHub pre-release.

Galaxy publish is deferred.

## Section 1 — Work Ordering

Ordered by risk (runtime bugs first, docs last):

| # | Task | Risk level | Notes |
|---|---|---|---|
| 1 | Revert debug commit `649b4c7` | Temp code in prod | First commit on branch — clean slate |
| 2 | F1: `handlers/main.yml` — rename `mongodb_net_bindip` → `mongodb_net_bindIp` (mongod + mongos) + grep audit entire repo for both spellings | **Runtime bug** — undefined var on restart handler fire | Grep: `mongodb_net_bindip`, `mongos_net_bindip` |
| 3 | **Trigger `workflow_dispatch` on branch** (parallel from here) | Unknown nightly CI failures | `gh workflow run molecule.yml --ref fix/v2-stabilization` |
| 4 | F7: `tasks/configure.yml` — add `no_log: true` + `apply: {no_log: true}` to `include_role` block | Security: credentials visible in logs | `no_log` on `include_role` alone does not propagate to inner tasks — must use `apply:` |
| 5 | F5: `vars/main.yml` — remove `vault_token`/`vault_url` env lookups | Contradicts CHANGELOG v2 removal claim | |
| 6 | F4: `defaults/main.yml` — remove `mongodb_reconfigure` stale alias | User-facing API confusion (correct: `mongodb_replication_reconfigure`) | |
| 7 | F2/F3: remove orphaned templates (`mongodb.logrotate.j2`, `mongos.logrotate.j2`, `mongodb.service.j2`) | Dead code | Confirm no dynamic `template:` path references before deleting |
| 8 | F6: `docs/SUPPORT-MATRIX.md` — add explicit Debian 12 arm64 exclusion note | Missing docs info | |
| 9 | Fix nightly failures (incorporate into branch) | Unknown scope | See Section 2 |
| 10 | Version bump: `galaxy.yml` + `meta/main.yml` → `2.0.0-rc1` | Release metadata | |
| 11 | CHANGELOG entry (after nightly green — content is final by then) | Release hygiene | |

## Section 2 — Nightly Validation Strategy

### Trigger

```bash
gh workflow run molecule.yml --ref fix/v2-stabilization
```

Branch must be pushed to `origin` first. `workflow_dispatch` activates the `molecule-nightly` job (`if: schedule || workflow_dispatch`). The nightly job has no pre-build amd64 images step — not required for these three scenarios.

### Scenarios

| Scenario | Tests | Known risk |
|---|---|---|
| `debian12-mongo60` | MongoDB 6.0 deprecated tier | `mongodb_allow_eol_version: true` already set in `converge.yml` — risk is repo availability / EOL package behaviour |
| `rhel8` | RHEL 8 + Python 3.9 install path | Different pip/collection install behaviour from Python 3.12 |
| `arm64-ubuntu2204` | arm64 via QEMU emulation | Slow (15–30 min); QEMU setup via `docker/setup-qemu-action@v3` already in workflow |

### Process

Trigger after task 2 (F1 fix). Since all three scenarios have never run, expect failures unrelated to the findings. Fix failures on the same branch. Re-trigger until all three are green. Distinguish infrastructure issues from role issues before treating results as authoritative.

## rc1 Tag Criteria (Definition of Done)

| Condition | Required |
|---|---|
| 5 PR-blocking molecule scenarios green | Already passing — verify not regressed |
| 3 nightly scenarios green | Must validate |
| All 11 Section 1 tasks complete | Must complete |
| `galaxy.yml` + `meta/main.yml` version = `2.0.0-rc1` | Must update |
| CHANGELOG entry for rc1 | Must write |

### Tag command (after merge to main)

```bash
git tag -a v2.0.0-rc1 -m "v2.0.0 release candidate 1" HEAD
git push origin v2.0.0-rc1
```

Create GitHub Release as **pre-release** (not GA). Attach CHANGELOG rc1 section in release body.

## Prerequisites Before Branching

```bash
# In main worktree
git pull --ff-only origin main   # brings local main to d56fd80
git worktree remove .claude/worktrees/refactor-v2.0-foundation  # safe — fully merged
git checkout -b fix/v2-stabilization
git push -u origin fix/v2-stabilization
```

## Commit Structure (recommended)

```
revert: undo temp diagnostic commit 649b4c7
fix(handlers): rename mongodb_net_bindip → mongodb_net_bindIp (F1 runtime bug)
fix(configure): add no_log to include_role credential block (F7)
fix(vars): remove vault_token/vault_url env lookups (F5)
fix(defaults): remove mongodb_reconfigure stale alias (F4)
chore: remove orphaned logrotate and service templates (F2/F3)
docs(support-matrix): add Debian 12 arm64 exclusion note (F6)
chore: fix nightly scenario failures [added after nightly results]
chore(release): bump version to 2.0.0-rc1
docs(changelog): add v2.0.0-rc1 entry
```
