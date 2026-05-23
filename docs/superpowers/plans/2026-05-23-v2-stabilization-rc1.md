# v2.0.0-rc1 Stabilization Release — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 post-merge findings + revert debug commit + validate 3 nightly molecule scenarios → tag `v2.0.0-rc1`.

**Architecture:** Single branch `fix/v2-stabilization` off updated `main`. Runtime bug (F1) fixed first + nightly triggered early to discover unknown CI failures in parallel with remaining cleanup. All changes in one PR; merge then tag.

**Tech Stack:** Ansible role YAML, Jinja2 templates, Molecule + Docker, GitHub Actions, yamllint, ansible-lint

---

## File Map

| File | Change |
|---|---|
| `handlers/main.yml` | F1: rename `mongodb_net_bindip` → `mongodb_net_bindIp` (lines 32, 71) |
| `handlers/restart_mongodb.yml` | F1: rename `mongodb_net_bindip` → `mongodb_net_bindIp` (line 28) |
| `handlers/restart_mongos.yml` | F1: rename `mongos_net_bindip` → `mongos_net_bindIp` (line 28) |
| `tasks/configure.yml` | F7: add `no_log: true` + `apply: {no_log: true}` to all 3 `include_role` blocks |
| `vars/main.yml` | F5: remove vault_token/vault_url env lookup block (lines 45–47) |
| `defaults/main.yml` | F4: remove `mongodb_reconfigure: false` stale alias (line 130) |
| `README.md` | F4: update 3 occurrences of `mongodb_reconfigure` → `mongodb_replication_reconfigure` |
| `templates/mongodb.logrotate.j2` | F2: delete file |
| `templates/mongos.logrotate.j2` | F2: delete file |
| `templates/mongodb.service.j2` | F3: delete file |
| `docs/SUPPORT-MATRIX.md` | F6: add Debian 12 arm64 exclusion note |
| `CHANGELOG.md` | Rename `[Unreleased] — v2.0.0` → `[2.0.0-rc1]` + add stabilization section |
| `tasks/replicaset.yml` | Revert: remove 2 debug tasks + restore `no_log: true` (via git revert) |

---

## Task 1: Bootstrap — Pull main and create branch

**Files:** none modified

- [ ] **Step 1: Verify you are in the main worktree (not the refactor worktree)**

```bash
pwd
# Expected: /path/to/ansible-role-mongodb  (NOT .../worktrees/...)
git branch --show-current
# Expected: main
```

- [ ] **Step 2: Pull origin/main to get v2 code locally**

```bash
git pull --ff-only origin main
```

Expected: `Fast-forward` with many files updated. HEAD should move to `d56fd80`.

```bash
git rev-parse HEAD
# Expected: d56fd807f9034cc72883eeb212b9b32334e0d2af
```

- [ ] **Step 3: Remove the merged worktree (safe — fully in main)**

```bash
git worktree remove .claude/worktrees/refactor-v2.0-foundation
```

Expected: no error. If it says "has untracked files", inspect first (`git -C .claude/worktrees/refactor-v2.0-foundation status`).

- [ ] **Step 4: Create and push the stabilization branch**

```bash
git checkout -b fix/v2-stabilization
git push -u origin fix/v2-stabilization
```

Expected: branch created and tracking `origin/fix/v2-stabilization`.

---

## Task 2: Revert debug commit 649b4c7

The commit added 2 diagnostic tasks to `tasks/replicaset.yml` and changed `no_log: true` → `no_log: false` on the root admin user create task.

**Files:** `tasks/replicaset.yml` (via git revert)

- [ ] **Step 1: Revert the commit**

```bash
git revert 649b4c7 --no-edit
```

Expected: creates a new commit with message `Revert "debug(replicaset): temp diagnostic on Phase 1.7a (CI debug, revert after)"`. The revert restores `no_log: true` and removes the two debug tasks.

- [ ] **Step 2: Verify the revert removed debug tasks and restored no_log**

```bash
grep -n "1.7-debug\|no_log" tasks/replicaset.yml | head -10
```

Expected output must NOT contain `1.7-debug`. Must contain `no_log: true` on the create root admin user task (Phase 1.7a). Should look like:

```
77:  no_log: true
```

- [ ] **Step 3: Syntax check**

```bash
ansible-lint tasks/replicaset.yml
```

Expected: no errors (warnings about `git_revert_sha` are acceptable).

- [ ] **Step 4: Push**

```bash
git push
```

---

## Task 3: F1 — Fix runtime bug: handler var names use undefined lowercase vars

`defaults/main.yml` defines `mongodb_net_bindIp` (camelCase 'I'). Four handler files reference `mongodb_net_bindip` (all-lowercase 'i') which is **undefined** — Ansible errors when these handlers fire.

**Files:** `handlers/main.yml`, `handlers/restart_mongodb.yml`, `handlers/restart_mongos.yml`

Note: The `_mongodb_net_bindip_item` and `_mongos_net_bindip_item` loop variable names do NOT need to change — they are playbook-local iterator variables, not role variables.

- [ ] **Step 1: Fix handlers/main.yml line 32**

```bash
grep -n "with_items.*mongodb_net_bindip\|with_items.*mongos_net_bindip" handlers/main.yml
```

Expected:
```
32:  with_items: "{{ mongodb_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
71:  with_items: "{{ mongos_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
```

Edit `handlers/main.yml` line 32:
```yaml
# Before:
  with_items: "{{ mongodb_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"

# After:
  with_items: "{{ mongodb_net_bindIp.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
```

Edit `handlers/main.yml` line 71:
```yaml
# Before:
  with_items: "{{ mongos_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"

# After:
  with_items: "{{ mongos_net_bindIp.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
```

- [ ] **Step 2: Fix handlers/restart_mongodb.yml line 28**

Edit `handlers/restart_mongodb.yml` line 28:
```yaml
# Before:
  with_items: "{{ mongodb_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"

# After:
  with_items: "{{ mongodb_net_bindIp.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
```

- [ ] **Step 3: Fix handlers/restart_mongos.yml line 28**

Edit `handlers/restart_mongos.yml` line 28:
```yaml
# Before:
  with_items: "{{ mongos_net_bindip.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"

# After:
  with_items: "{{ mongos_net_bindIp.split(',') | map('replace', '0.0.0.0', '127.0.0.1') | list }}"
```

- [ ] **Step 4: Grep audit — confirm no remaining lowercase references in executable files**

```bash
grep -rn "mongodb_net_bindip\b\|mongos_net_bindip\b" handlers/ tasks/ templates/ defaults/ vars/ molecule/
```

Expected: **zero matches**. If any remain, fix them before proceeding.

(References in `docs/`, `CHANGELOG.md`, `README.md` are documentation of the rename — intentionally lowercase there.)

- [ ] **Step 5: Syntax check**

```bash
yamllint handlers/main.yml handlers/restart_mongodb.yml handlers/restart_mongos.yml
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add handlers/main.yml handlers/restart_mongodb.yml handlers/restart_mongos.yml
git commit -m "fix(handlers): rename mongodb_net_bindip → mongodb_net_bindIp (F1 runtime bug)

Handlers used the undefined lowercase var. defaults/main.yml defines
mongodb_net_bindIp (camelCase). Four with_items lines corrected across
main.yml, restart_mongodb.yml, and restart_mongos.yml."
```

- [ ] **Step 7: Push**

```bash
git push
```

---

## Task 4: Trigger nightly workflow_dispatch

Run the 3 never-tested nightly scenarios in parallel with remaining cleanup tasks. Results guide Task 10.

**Files:** none modified

- [ ] **Step 1: Trigger nightly CI on the fix branch**

```bash
gh workflow run molecule.yml --ref fix/v2-stabilization
```

Expected: `Created workflow dispatch event for molecule.yml at fix/v2-stabilization`

- [ ] **Step 2: Note the run URL for monitoring**

```bash
gh run list --workflow=molecule.yml --branch=fix/v2-stabilization --limit=3
```

Note the run ID. Check progress at `https://github.com/maprangzth/ansible-role-mongodb/actions`. The 3 nightly scenarios (`debian12-mongo60`, `rhel8`, `arm64-ubuntu2204`) will appear under `molecule-nightly` job. `arm64-ubuntu2204` takes 15–30 minutes due to QEMU emulation.

- [ ] **Step 3: Continue with Tasks 5–9 while nightly runs**

Do not wait for nightly results here — proceed with cleanup tasks. Return to Task 10 after nightly completes.

---

## Task 5: F7 — Add no_log to include_role credential blocks

`tasks/configure.yml` contains 3 `include_role` blocks that pass admin credentials via `vars:`. Without `no_log`, these credentials appear in Ansible verbose output and CI logs.

**Files:** `tasks/configure.yml`

Important: `no_log: true` on the task level hides the task's var list in output. `apply: {no_log: true}` propagates to all tasks inside the included role. Both are required.

Limitation: `apply: {no_log: true}` only propagates one level into the included role — nested `include_tasks` within `community.mongodb` are not covered. This is the best protection available at the delegation boundary.

- [ ] **Step 1: Add no_log to the mongodb_mongod include_role block**

In `tasks/configure.yml`, find the `Configure mongod (standalone / replicaset member / shard data node)` task (~line 22). Add `no_log: true` at the task level and `apply: {no_log: true}` inside the `include_role:` block:

```yaml
# Before:
- name: Configure mongod (standalone / replicaset member / shard data node)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_mongod
  vars:

# After:
- name: Configure mongod (standalone / replicaset member / shard data node)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_mongod
    apply:
      no_log: true
  no_log: true
  vars:
```

- [ ] **Step 2: Add no_log to the mongodb_config include_role block**

Find the `Configure mongod as configsvr (config server replicaset)` task (~line 85):

```yaml
# Before:
- name: Configure mongod as configsvr (config server replicaset)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_config
  vars:

# After:
- name: Configure mongod as configsvr (config server replicaset)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_config
    apply:
      no_log: true
  no_log: true
  vars:
```

- [ ] **Step 3: Add no_log to the mongodb_mongos include_role block**

Find the `Configure mongos (query router)` task (~line 127):

```yaml
# Before:
- name: Configure mongos (query router)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_mongos
  vars:

# After:
- name: Configure mongos (query router)
  ansible.builtin.include_role:
    name: community.mongodb.mongodb_mongos
    apply:
      no_log: true
  no_log: true
  vars:
```

- [ ] **Step 4: Verify all 3 blocks have no_log**

```bash
grep -n "no_log\|include_role" tasks/configure.yml
```

Expected: 6 `no_log` lines total (2 per include_role block: one `apply:` level, one task level), 3 `include_role` lines.

- [ ] **Step 5: Syntax check**

```bash
yamllint tasks/configure.yml
ansible-lint tasks/configure.yml
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add tasks/configure.yml
git commit -m "fix(configure): add no_log to include_role credential blocks (F7)

Three include_role blocks pass mongodb_admin_pwd and related secrets via
vars:. Add no_log: true at task level + apply: {no_log: true} inside
include_role to suppress credentials in output and CI logs."
```

---

## Task 6: F5 — Remove vault_token/vault_url from vars/main.yml

CHANGELOG v2.0.0 Removed section states these vars were removed. They are still present in `vars/main.yml:45–47`, contradicting the CHANGELOG and leaking env var lookups into every play.

**Files:** `vars/main.yml`

- [ ] **Step 1: Remove the vault block**

In `vars/main.yml`, delete lines 45–47:

```yaml
# Remove these 3 lines entirely:
# === Vault placeholders (kept for v1 compatibility) ===
vault_token: "{{ lookup('env', 'VAULT_TOKEN') }}"
vault_url: "{{ lookup('env', 'VAULT_ADDR') }}"
```

The file should end with the replicaset groups block:

```yaml
# === Replicaset group discovery (per §5.1 per-replicaset execution) ===
mongodb_replicaset_groups: >-
  {{
    (groups.keys() | select('match', '^(' ~ mongodb_replication_host_group ~ '|'
                                          ~ mongodb_sharded_host_group ~ '[0-9]+|'
                                          ~ mongodb_config_host_group ~ ')$') | list)
  }}
```

- [ ] **Step 2: Confirm no remaining references in task/template files**

```bash
grep -rn "vault_token\|vault_url" handlers/ tasks/ templates/ defaults/
```

Expected: **zero matches**.

- [ ] **Step 3: Syntax check**

```bash
yamllint vars/main.yml
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add vars/main.yml
git commit -m "fix(vars): remove vault_token/vault_url env lookups (F5)

CHANGELOG v2.0.0 already listed these as removed. The vars were still
present in vars/main.yml, contradicting the documented API surface."
```

---

## Task 7: F4 — Remove mongodb_reconfigure stale alias

`defaults/main.yml` defines both `mongodb_replication_reconfigure: false` (correct v2 name, line 67) and `mongodb_reconfigure: false` (stale v1 alias, line 130). `README.md` examples use the stale name.

**Files:** `defaults/main.yml`, `README.md`

- [ ] **Step 1: Remove stale alias from defaults/main.yml**

In `defaults/main.yml`, delete line 130:

```yaml
# Remove this line:
mongodb_reconfigure: false
```

The line immediately before it is `mongos_daemon_name: mongos`. The line after is `mongodb_replication_replindexprefetch: all`. After deletion those two lines are adjacent.

- [ ] **Step 2: Update README.md — variable table entry**

In `README.md` (~line 387), find:

```yaml
mongodb_reconfigure: false             # Force reconfiguration even if not changed
```

Replace with:

```yaml
mongodb_replication_reconfigure: false # Force reconfiguration even if not changed
```

- [ ] **Step 3: Update README.md — example commands (2 occurrences)**

In `README.md` (~lines 595 and 600), find:

```bash
  -e '{mongodb_reconfigure: true, mongodb_security_authorization_enabled: false, mongodb_admin_update_password: true, mongodb_users_update_password: true, mongodb_exporter_force_install: true}'
```

Replace `mongodb_reconfigure: true` with `mongodb_replication_reconfigure: true`:

```bash
  -e '{mongodb_replication_reconfigure: true, mongodb_security_authorization_enabled: false, mongodb_admin_update_password: true, mongodb_users_update_password: true, mongodb_exporter_force_install: true}'
```

And (~line 600):

```bash
  -e '{mongodb_reconfigure: true}'
```

Replace with:

```bash
  -e '{mongodb_replication_reconfigure: true}'
```

- [ ] **Step 4: Verify no remaining stale references in executable files**

```bash
grep -rn "\bmongodb_reconfigure\b" defaults/ vars/ tasks/ handlers/ templates/ README.md
```

Expected: **zero matches**. References in `docs/` are historical documentation — leave as-is.

- [ ] **Step 5: Syntax check**

```bash
yamllint defaults/main.yml
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add defaults/main.yml README.md
git commit -m "fix(defaults): remove mongodb_reconfigure stale alias (F4)

mongodb_replication_reconfigure is the correct v2 var name (defined at
line 67). The legacy alias at line 130 was never wired to any task.
README examples updated to use the correct name."
```

---

## Task 8: F2/F3 — Remove orphaned templates

Three templates have no task that renders them. They are dead code.

**Files:** `templates/mongodb.logrotate.j2`, `templates/mongos.logrotate.j2`, `templates/mongodb.service.j2`

- [ ] **Step 1: Confirm no task references these templates**

```bash
grep -rn "mongodb.logrotate\|mongos.logrotate\|mongodb.service" tasks/ handlers/
```

Expected: **zero matches**. If any match is found, do not delete — investigate the reference first.

- [ ] **Step 2: Delete the templates**

```bash
git rm templates/mongodb.logrotate.j2 templates/mongos.logrotate.j2 templates/mongodb.service.j2
```

Expected: 3 files deleted and staged.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove orphaned logrotate and service templates (F2/F3)

No task renders mongodb.logrotate.j2, mongos.logrotate.j2, or
mongodb.service.j2. Dead code removed."
```

---

## Task 9: F6 — Add Debian 12 arm64 exclusion to SUPPORT-MATRIX.md

The Debian/Ubuntu table shows `✅` under `amd64 + arm64` for all Debian 12 (bookworm) rows, but bookworm has NO arm64 mongodb-org-server packages (only client tools). This contradicts `vars/main.yml` which correctly excludes arm64 from the Debian 12 support matrix.

**Files:** `docs/SUPPORT-MATRIX.md`

- [ ] **Step 1: Add an explicit warning note to the Notes section**

In `docs/SUPPORT-MATRIX.md`, in the `## Notes` section, add after the existing notes:

```markdown
- **Debian 12 (bookworm) arm64**: The `amd64 + arm64` column header is misleading for bookworm rows.
  Debian 12 has **NO arm64 `mongodb-org-server` packages** for any MongoDB version — only client
  tools (mongosh, atlas-cli) are published for arm64. The `vars/main.yml` support matrix reflects
  this: `Debian: { "12": ["x86_64"] }` for all versions. Do not deploy Debian 12 arm64 nodes.
```

- [ ] **Step 2: Verify the note appears in the file**

```bash
grep -n "bookworm arm64\|no arm64" docs/SUPPORT-MATRIX.md
```

Expected: at least 1 match containing the note.

- [ ] **Step 3: Commit**

```bash
git add docs/SUPPORT-MATRIX.md
git commit -m "docs(support-matrix): add Debian 12 arm64 exclusion note (F6)

The amd64 + arm64 column is misleading for bookworm rows. Debian 12 has
no arm64 mongodb-org-server packages — only client tools are arm64.
Added explicit note to avoid operator confusion."
```

---

## Task 10: Fix nightly scenario failures

Return here after Task 4 nightly run completes. Check results and fix any failures.

**Files:** scenario-specific (unknown until CI results known)

- [ ] **Step 1: Check nightly run results**

```bash
gh run list --workflow=molecule.yml --branch=fix/v2-stabilization --limit=5
```

For the most recent run, get the run ID and check per-job status:

```bash
gh run view <RUN_ID> --log-failed 2>&1 | head -100
```

Or view in browser: `https://github.com/maprangzth/ansible-role-mongodb/actions`

- [ ] **Step 2: For each failed scenario — reproduce locally if possible**

```bash
# For local molecule runs, use Python 3.11 venv with ansible-core <2.18
# (molecule_plugins create.yml has Ansible 2.21 strict-conditional bug)
python3.11 -m venv /tmp/mol-venv
source /tmp/mol-venv/bin/activate
pip install "ansible-core<2.18" molecule "molecule-plugins[docker]" docker pymongo packaging
ansible-galaxy collection install -r requirements.yml

# Run specific scenario (example: rhel8)
molecule test -s rhel8
```

For `arm64-ubuntu2204` local run, QEMU must be installed first:
```bash
docker run --rm --privileged tonistiigi/binfmt --install amd64
```

- [ ] **Step 3: Apply fixes in targeted commits per scenario**

Fix failures directly in the relevant files. Commit each scenario's fix separately:

```bash
git add <changed files>
git commit -m "fix(molecule/<scenario>): <brief description of fix>"
```

- [ ] **Step 4: Re-trigger nightly after fixes**

```bash
git push
gh workflow run molecule.yml --ref fix/v2-stabilization
```

Repeat until all 3 nightly scenarios pass. Verify:

```bash
gh run list --workflow=molecule.yml --branch=fix/v2-stabilization --limit=5
# All molecule-nightly jobs should show: ✓ (completed successfully)
```

---

## Task 11: CHANGELOG + version metadata

Write rc1 CHANGELOG entry after nightly scenarios are green (content is final).

**Files:** `CHANGELOG.md`

- [ ] **Step 1: Rename [Unreleased] heading to [2.0.0-rc1]**

In `CHANGELOG.md`, change the heading:

```markdown
# Before:
## [Unreleased] — v2.0.0

# After:
## [2.0.0-rc1] — 2026-05-23
```

- [ ] **Step 2: Add stabilization fixes sub-section**

Under the `## [2.0.0-rc1]` section, add a `### Fixed` subsection BEFORE the existing `### Added` block:

```markdown
### Fixed (stabilization — post-PR #1 findings)

- **`handlers/main.yml`, `restart_mongodb.yml`, `restart_mongos.yml`** — `mongodb_net_bindip` / `mongos_net_bindip` renamed to `mongodb_net_bindIp` / `mongos_net_bindIp`. Lowercase var names were undefined at runtime; restart notification path would error on first config change.
- **`tasks/configure.yml`** — added `no_log: true` + `apply: {no_log: true}` to all three `include_role` credential blocks to suppress admin passwords in output and CI logs.
- **`vars/main.yml`** — removed `vault_token` / `vault_url` env-lookup vars. Listed as removed in CHANGELOG but still present; now actually removed.
- **`defaults/main.yml`** — removed `mongodb_reconfigure` stale alias (correct name: `mongodb_replication_reconfigure`). README examples updated.
- **`templates/`** — deleted orphaned `mongodb.logrotate.j2`, `mongos.logrotate.j2`, `mongodb.service.j2` (no task rendered them).
- **`docs/SUPPORT-MATRIX.md`** — added explicit note: Debian 12 (bookworm) has no arm64 `mongodb-org-server` packages.
- **`tasks/replicaset.yml`** — reverted temp diagnostic commit that leaked into main (restored `no_log: true` on root admin create task).
```

- [ ] **Step 3: Update the footer links**

At the bottom of `CHANGELOG.md`, update:

```markdown
# Before:
[Unreleased]: https://github.com/maprangzth/ansible-role-mongodb/compare/v1.6.5...HEAD

# After:
[2.0.0-rc1]: https://github.com/maprangzth/ansible-role-mongodb/compare/v1.6.5...v2.0.0-rc1
[Unreleased]: https://github.com/maprangzth/ansible-role-mongodb/compare/v2.0.0-rc1...HEAD
```

- [ ] **Step 4: Syntax check**

```bash
yamllint CHANGELOG.md 2>/dev/null || echo "not yaml — ok"
# Check markdown is well-formed:
grep "^## \[" CHANGELOG.md
```

Expected output includes `## [2.0.0-rc1] — 2026-05-23` and `## [v1.6.5]`.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): add v2.0.0-rc1 entry

Rename [Unreleased] to [2.0.0-rc1]. Document stabilization fixes
(F1-F7 findings + debug commit revert) under new Fixed section."
```

---

## Task 12: PR, verify CI, merge, and tag

**Files:** none modified

Note on version metadata: `galaxy.yml` does not exist in this repo (not needed — Ansible roles are versioned by git tags, not a manifest file). `meta/main.yml` has no `version:` field (Galaxy reads the tag). The "version bump" from the spec is entirely fulfilled by the `v2.0.0-rc1` annotated tag in Step 5.

- [ ] **Step 1: Verify all 5 PR-blocking scenarios are green on this branch**

```bash
gh run list --workflow=molecule.yml --branch=fix/v2-stabilization --limit=10
```

Look for a run triggered by `push` (not `workflow_dispatch`). All 5 matrix scenarios in `molecule-pr` job must show ✓.

If not green, fix before creating PR.

- [ ] **Step 2: Create PR**

```bash
gh pr create \
  --title "fix: v2.0.0-rc1 stabilization — 7 post-merge findings + nightly CI" \
  --body "$(cat <<'EOF'
## Summary

- Fixes F1 runtime bug: `mongodb_net_bindip` → `mongodb_net_bindIp` in 4 handler files (undefined var on restart notification path)
- Adds `no_log` protection to 3 `include_role` credential blocks in `tasks/configure.yml`
- Removes stale `vault_token`/`vault_url` env lookups from `vars/main.yml`
- Removes `mongodb_reconfigure` stale alias from `defaults/main.yml` + README
- Removes 3 orphaned templates (logrotate + service)
- Fixes `docs/SUPPORT-MATRIX.md` Debian 12 arm64 exclusion
- Reverts temp debug commit `649b4c7` (restores `no_log: true`)
- Validates 3 nightly scenarios (debian12-mongo60, rhel8, arm64-ubuntu2204)

## Test plan

- [ ] All 5 PR-blocking molecule scenarios green
- [ ] All 3 nightly scenarios green (triggered via workflow_dispatch before merge)
- [ ] `ansible-lint` + `yamllint` pass
- [ ] No remaining `mongodb_net_bindip` (lowercase) in handlers/tasks/templates

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Merge PR after all CI green**

```bash
gh pr merge --squash --delete-branch
```

Or use GitHub UI. Confirm `molecule-pr` (5 scenarios) AND `molecule-nightly` (3 scenarios) are all ✓ before merging.

- [ ] **Step 4: Update local main**

```bash
git checkout main
git pull --ff-only origin main
git rev-parse HEAD  # note this SHA — it is the tag target
```

- [ ] **Step 5: Create annotated tag**

```bash
git tag -a v2.0.0-rc1 -m "v2.0.0 release candidate 1

All 5 PR-blocking + 3 nightly molecule scenarios green.
See CHANGELOG.md [2.0.0-rc1] for full change list."
git push origin v2.0.0-rc1
```

- [ ] **Step 6: Create GitHub pre-release**

```bash
gh release create v2.0.0-rc1 \
  --title "v2.0.0-rc1 — Release Candidate 1" \
  --prerelease \
  --notes "$(cat <<'EOF'
Release candidate for v2.0.0. All CI gates (8 molecule scenarios) green.

**Breaking changes:** This is a clean-break refactor from v1.x. See [Migration Guide](docs/MIGRATION-v2.md).

**Changes in this RC:** See [CHANGELOG.md](CHANGELOG.md#200-rc1--2026-05-23).

**Not included:** Galaxy publish (deferred), sharding modernization (sub-project 2), backup feature (sub-project 3).
EOF
)"
```

Expected: URL to pre-release printed. Verify at `https://github.com/maprangzth/ansible-role-mongodb/releases`.

---

## Verification: Definition of Done

Run this checklist before calling rc1 complete:

```bash
# 1. All handler lowercase vars gone
grep -rn "mongodb_net_bindip\b\|mongos_net_bindip\b" handlers/ tasks/ templates/ defaults/ vars/
# Expected: zero matches

# 2. Vault vars gone
grep -rn "vault_token\|vault_url" vars/ defaults/ tasks/ handlers/
# Expected: zero matches

# 3. Stale alias gone
grep -rn "\bmongodb_reconfigure\b" defaults/ vars/ tasks/ handlers/ README.md
# Expected: zero matches

# 4. Orphaned templates gone
ls templates/ | grep -E "logrotate|mongodb\.service"
# Expected: no output

# 5. Tag exists
git tag -l "v2.0.0-rc1"
# Expected: v2.0.0-rc1

# 6. GitHub release is pre-release
gh release view v2.0.0-rc1 --json isPrerelease -q '.isPrerelease'
# Expected: true
```
