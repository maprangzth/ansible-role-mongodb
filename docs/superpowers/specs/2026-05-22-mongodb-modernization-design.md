# 2026-05-22 — ansible-role-mongodb v2.0.0 Foundation Refactor

**Status:** Design / pending implementation plan
**Owner:** maprangzth
**Repo:** [maprangzth/ansible-role-mongodb](https://github.com/maprangzth/ansible-role-mongodb) (hard fork of `superset1/ansible-role-mongodb`, unmaintained since 2023)
**Spec scope:** Sub-project 1 only — version + OS matrix refactor. Sub-projects 2 (sharding modernization) and 3 (backup feature) get separate specs after v2.0.0 ships.

**Revision history:**
- 2026-05-22 v0.9 — initial draft
- 2026-05-22 v1.0 — revised after council fan-out #1 (GPT-5.5 + Gemini 3.1 Pro) flagged ~23 critical issues
- 2026-05-23 v1.1 — revised after council fan-out #2 found ~16 remaining issues (bootstrap auth flow invalid, per-replicaset execution, RHEL 8 Python conflict, TLS validation gaps, master branch intent, etc.). Two Gemini "fatal" findings fact-checked against MongoDB repos + context7 and disproven (community.mongodb roles exist; MongoDB 6.0 has Debian 12 repo).

---

## 1. Goal

Modernize the role so it cleanly supports MongoDB 7.0 + 8.0 on currently-released RHEL / Debian / Ubuntu LTS targets, drop ~9 years of legacy support code (MongoDB 3.4–5.0, SSL legacy block, MMS agent, Amazon Linux), and rebuild test + CI infrastructure. Ship as `maprangzth.mongodb` v2.0.0 — a clean break with no backward-compatibility shim layer, guarded by explicit fail-fast checks for removed v1 variables.

## 2. Decision summary

| Question | Decision |
|---|---|
| Release shape | v2.0.0 clean break, no var shim, explicit fail tasks for removed v1 vars |
| MongoDB versions supported | 8.0 (default, LTS until Oct 2029), 7.0 (LTS until Aug 2027), 6.0 (deprecated tier — opt-in via `mongodb_allow_eol_version: true`, warning emitted, no new features) |
| MongoDB versions dropped | 3.4, 3.6, 4.0, 4.2, 4.4, 5.0 |
| Default `mongodb_version` | `"8.0"` |
| Major-version upgrade safety | Preflight detects installed MongoDB major version; fails unless `mongodb_allow_major_upgrade: true` is set or installed major matches target |
| OS — Primary support (PR-blocking CI) | Debian 12, Ubuntu 22.04, Ubuntu 24.04, RHEL/Rocky/Alma 9 |
| OS — Nightly only | RHEL/Rocky/Alma 8 (Python 3.9 install path, slower), MongoDB 6.0 deprecated-tier smoke (one combo), arm64 smoke (one OS) |
| OS support disclaimer | "RHEL family" tested via Rocky Linux as the RHEL-compatible proxy. AlmaLinux assumed compatible but not in CI. |
| OS — Dropped | Amazon Linux (all), Debian ≤ 10, Ubuntu ≤ 20.04, RHEL ≤ 7 |
| OS — Out of scope for v2.0 | Debian 11 (EOL Aug 2026), Debian 13, Ubuntu 26.04, RHEL 10 — add as MongoDB publishes official repos |
| Architecture | amd64 + arm64 (detect at runtime, separate apt/rpm/exporter arch vars per §6.5) |
| Features dropped | `mongodb_net_ssl_config` legacy block (TLS-only henceforth), MMS agent + `mongodb_cloud_*` vars, MongoDB free cloud monitoring config section |
| Features kept | mongodb-exporter (pinned version + checksum, not "latest"), keyfile auth, TLS cluster file, logrotate, disable_thp, custom roles, custom users |
| TLS schema | `mongodb_net_tls_*` flat vars (see §6.6); legacy `mongodb_net_ssl_*` rejected at validate time |
| Approach (architectural shift) | **B-spike (3 days) → decide** (see §4) |
| Dependency floor | `ansible-core >= 2.15`, `pymongo >= 4.6`, target Python `>= 3.9`, `community.mongodb >= 1.7` (unconditional — both approaches use it for `mongodb_user`, `mongodb_replicaset`, `mongodb_shard`, `mongodb_status`) |
| CI | GitHub Actions: push/PR + scheduled nightly + manual dispatch |
| Sharding scope in v2.0 | Preserve-not-regress only — existing flow keeps working. Modernization (config-shard, etc.) deferred to sub-project 2. |
| Repo strategy | Hard fork, rename `master` → `main` (keep `master` as legacy pointer for 1 release), branch `v1.x` for security backports, namespace `maprangzth` |
| Galaxy publishing | Decided at v2.0.0 GA (after 1 week of `v2.0.0-rc*` dogfooding). Until GA, install via git URL only. |

## 3. Non-goals

- In-place data upgrade across MongoDB major versions (4.4 → 8.0) — operator runs MongoDB's documented step-wise upgrade procedure (`4.4 → 5.0 → 6.0 → 7.0 → 8.0`, setting FCV between each step) before applying the role. MongoDB engine does not support skipping major versions.
- TLS cert lifecycle / PKI — operator provides `.pem` files; role only places them with correct perms and references them in config.
- Backup orchestration — separate sub-project, separate spec.
- Sharding flow modernization (config-shard, etc.) — separate sub-project. v2.0 preserves existing behavior.
- Performance benchmarking vs v1.x.
- FCV auto-bump (operator runs `setFeatureCompatibilityVersion()` manually after major upgrade).

## 4. Architectural decision: B-spike → Approach B or Hybrid

Two viable approaches considered, plus a 3-day spike gate.

### Approach A — Strip-and-modernize in-place
Keep current task structure. Surgically delete legacy code paths. Own templates and per-OS vars. Lower implementation risk, higher long-term maintenance.

### Approach B — Delegate to `community.mongodb`
Replace install / configure / replicaset tasks with calls into the upstream `community.mongodb` collection's roles + modules. Keep value-add (user mgmt with `community.mongodb.mongodb_user`, exporter, logrotate). Higher implementation risk, lower long-term maintenance.

### Pre-spike verification task

Before starting the spike, verify these `community.mongodb` artifacts exist with expected names and capabilities (council flagged that names were assumed):

- Role `community.mongodb.mongodb_repository` — installs apt/yum repo for given MongoDB version + OS
- Role `community.mongodb.mongodb_mongod` — installs/configures mongod, exposes `mongodb_net_bindIp`, `mongodb_replication_replSetName`, `mongodb_storage_dbPath`, `mongodb_security_keyFile`, etc.
- Role `community.mongodb.mongodb_config` — same for config server (`--configsvr`)
- Role `community.mongodb.mongodb_mongos` — installs/configures mongos
- Module `community.mongodb.mongodb_replicaset` — idempotent replicaset init
- Module `community.mongodb.mongodb_status` — polls replicaset status (potential replacement for our `library/mongodb_status_edited.py`)
- Module `community.mongodb.mongodb_shard` — adds shards to mongos

Record verification result + collection version tested in `docs/superpowers/specs/2026-05-22-spike-report.md` before flow tests start.

### Decision gate: 3-day B-spike before committing

Run a time-boxed 3-day prototype of Approach B against five flows (council added MongoDB version coverage):

1. **TLS cluster certificate** (separate `clusterFile` from `certificateKeyFile`)
2. **Keyfile auth** lifecycle (content from `mongodb_security_keyfile_content` var, deployed identically to all members, mode 0400, owner per OS)
3. **3-node replicaset init** via `community.mongodb.mongodb_replicaset` + status convergence poll (compare `community.mongodb.mongodb_status` vs our custom `library/mongodb_status_edited.py`)
4. **Sharded cluster setup** (configsvr replicaset + 2 shards × 3 members + 1 mongos)
5. **MongoDB version sweep**: run flows 1–3 against MongoDB 6.0, 7.0, and 8.0 — verify upstream templates render correct config for each version's deprecations

### Testable pass criteria (revised per council)

All criteria must hold simultaneously; failure of any one criterion = fall back to Hybrid.

**Per-flow assertions:**

| Flow | Assertion |
|---|---|
| TLS cluster cert | `openssl s_client -connect mongo01:27017 -CAfile ca.pem` reports correct cert chain; inter-node auth uses cluster cert (check `db.adminCommand({getCmdLineOpts: 1})` shows `clusterFile` set) |
| Keyfile auth | `stat /etc/mongodb-keyfile` → mode 0400, owner per OS; same SHA256 across all 3 members; `mongod` startup logs report keyfile loaded |
| Replicaset init | `rs.status()` returns 1 PRIMARY + 2 SECONDARY within 60s; writes on PRIMARY visible on SECONDARY within 5s; idempotent rerun reports no changed tasks |
| Sharded cluster | `sh.status()` from mongos lists 2 shards; `sh.enableSharding("testdb")` succeeds; insert via mongos lands on a shard (verifiable via `getShardDistribution()`) |
| Version sweep | Each MongoDB version (6.0, 7.0, 8.0) reaches healthy replicaset state without template overrides |

**Code-size limits (revised — task-count not LOC):**

- Each custom wrapper task (anything outside `include_role` + var binding) ≤ 8 tasks per flow file
- Total custom wrapper tasks across all 5 flows ≤ 40
- Excluded from count: comments, blank lines, `name:`, `tags:`, `when:` clauses that only pass through, standard `include_role` boilerplate
- No upstream template override required (no `template_overrides` directory, no monkey-patched `mongod.conf.j2`, no `/etc/mongod.conf` post-render edit)
- No service unit override (no `/etc/systemd/system/mongod.service.d/*.conf` written by us)

**Idempotency:**

- Use `molecule idempotence` phase (second converge) — must report 0 changed tasks
- Documented allowlist for known-flaky changed reports: `apt update`, `yum makecache`, package facts gathering, repo metadata refresh — any other changed task fails idempotency

**Workaround classification:**

- **Acceptable workaround:** small var massaging task before `include_role`, custom `community.mongodb.mongodb_shell` task with explicit Mongo command, additional `assert` or `wait_for` task
- **Disqualifying workaround:** template override, config file post-render edit (`lineinfile`/`replace`/`blockinfile` on `/etc/mongod.conf`), service unit override, forking upstream role into the role tree

**Timebox failure semantics:**

- 3 calendar days from spike start (skip weekends if needed, but document)
- If 5 flows are not all completed with above evidence by day 3 end → **fail to Hybrid** (incomplete evidence == fail; no extension)

### Decision rule

- ✅ All pass criteria hold + all 5 flows complete + verification step §4 pre-spike passed → commit Approach B for v2.0.0.
- ❌ Any criterion fails or any flow incomplete by timebox → fall back to **Hybrid**: ship Approach A for v2.0.0 + record `docs/ROADMAP-v3.md` as evaluation note (not commitment to migrate).

### Spike deliverables

- Branch: `spike/community-mongodb-eval`
- `tests/spike-inventory/` with configsvr + 2 shard + 1 mongos host group
- Report file: `docs/superpowers/specs/2026-05-22-spike-report.md` covering pre-spike verification, each flow's evidence (commands + output), code-size measurement, idempotency results, decision

## 5. Architecture (post-spike, both paths)

```
inventory groups: mongo_standalone | mongo_cluster | mongo_shard_* | mongocfg_servers | mongos_servers
                                       │
                                       ▼
playbook: roles: [maprangzth.mongodb]
                                       │
                                       ▼
tasks/main.yml — host classification (UNCHANGED logic, slimmed code)
  1. set_fact mongodb_main_group
  2. include_vars per OS (Approach A) | include_role community.mongodb.mongodb_repository (Approach B)
  3. set_fact mongodb_master (deterministic — first non-arbiter host in group, see §5.5)
  4. include_tasks install.requirements (python3.9+, pymongo>=4.6)
  5. include_tasks validate.yml  (assertion gate — §8)
  6. include_tasks install (apt/yum repo + pkg) | delegate to upstream
  7. branch on group:
       data nodes  → configure_mongodb.yml | community.mongodb.mongodb_mongod
       configsvr   → configure_mongodb.yml --configsvr | community.mongodb.mongodb_config
       mongos      → configure_mongos.yml  | community.mongodb.mongodb_mongos
  8. replicaset init (master host only, delegate_to: mongodb_master_host) — see §5.4 bootstrap sequence
  9. sharding (mongos master only) — community.mongodb.mongodb_shard (PRESERVE-NOT-REGRESS in v2.0)
 10. create_users.yml (master only) — community.mongodb.mongodb_user, no_log: true
 11. additional_commands.yml (opt-in via tag, no_log: true)
 12. mongodb-exporter.yaml (if enabled)
```

### 5.1 Module execution location (council added)

**Per-replicaset execution model (council #2 fix):** A sharded inventory contains multiple replicaset groups (`mongocfg_servers`, `mongo_shard_1`, `mongo_shard_2`, ...). Global `run_once: true` would initialize only one. Instead, the role builds a `mongodb_replicaset_groups` fact (list of group names that need replicaset init) and loops over it, computing one master per group.

```yaml
- name: Build per-replicaset master map
  ansible.builtin.set_fact:
    mongodb_replicaset_masters: >-
      {{
        dict(
          mongodb_replicaset_groups | zip(
            mongodb_replicaset_groups | map('extract', groups) | map('first')
          )
        )
      }}
  run_once: true
```

Then per-replicaset tasks loop over `mongodb_replicaset_groups`, delegating to `mongodb_replicaset_masters[item]` for each. Not relying on play-level `run_once`.

| Task | Execution host | Connection target | Rationale |
|---|---|---|---|
| `community.mongodb.mongodb_repository` (role) | each target node | n/a (apt/yum local) | repo per-host |
| `community.mongodb.mongodb_mongod` (role) | each target node | n/a (writes local config) | per-host config |
| `community.mongodb.mongodb_replicaset` (module) | loop over `mongodb_replicaset_groups`, `delegate_to: mongodb_replicaset_masters[item]` | `login_host: 127.0.0.1` (on master) | one rs.initiate per replicaset (configsvr, each shard) |
| `community.mongodb.mongodb_status` (module) | same as above | same as above | poll each replicaset independently |
| `community.mongodb.mongodb_user` (module) | loop over replicaset groups, `delegate_to: mongodb_replicaset_masters[item]` per group | same | per-replicaset auth bootstrap |
| `community.mongodb.mongodb_shard` (module) | `delegate_to: groups[mongos_host_group][0]`, `run_once: true` (single mongos coordinates shard add) | first mongos host | one sh.addShard per shard |
| mongodb-exporter install | each target node | n/a | per-host binary install |

All `community.mongodb` modules require `pymongo` **on the executing host** (the `delegate_to` target). Since execution targets are MongoDB nodes themselves (not the controller), `pymongo >= 4.6` must be installed on every node by `tasks/install.requirements.yml`.

### 5.2 PyMongo placement decision

`pymongo` and Python 3.9+ installed **on each target node** (not controller) via `tasks/install.requirements.yml`. Modules execute on target nodes by default with `delegate_to: mongodb_master_host` (which is itself a target node) for cluster-scope operations. This matches v1.x behavior and avoids controller dependency drift across operator environments.

### 5.3 mongodb_master selection (deterministic, per-replicaset)

For each replicaset group `g`, `mongodb_replicaset_masters[g]` is computed as: first host in `groups[g]` (alphabetically sorted by `inventory_hostname`) whose `mongodb_arbiter` is falsy (using truthiness check, not "not defined"):

```jinja
{{ groups[g] | sort | reject('match', '^$')
   | rejectattr_via_hostvars('mongodb_arbiter', 'eq', True)
   | first }}
```

Equivalent pseudocode: `first(sorted(g) where not bool(hostvars[host].mongodb_arbiter | default(false)))`.

The truthiness check correctly handles `mongodb_arbiter: false` (which v1.x's "not defined" check incorrectly excluded). Documented in README so operators can predict master selection per replicaset.

### 5.4 Bootstrap auth sequence (council #1 — rewrite)

**MongoDB constraint:** Setting `security.keyFile` in `mongod.conf` automatically enables `security.authorization`. The two cannot be decoupled (verified against MongoDB 6.0/7.0/8.0 docs). Prior 3-phase plan with "keyfile set but auth disabled" was invalid. Replaced with this 2-phase sequence:

```
Phase 1 — initial bring-up (no keyfile, no auth, localhost exception window):
  1. Install MongoDB packages on all members
  2. Render mongod.conf WITHOUT security.keyFile and WITHOUT security.authorization
     (replication.replSetName IS set so members can form a replicaset)
  3. Start mongod on all members
  4. wait_for port 27017 on each member
  5. Per replicaset group, on its master (delegate_to mongodb_replicaset_masters[g]):
       community.mongodb.mongodb_replicaset → rs.initiate({...})
  6. Per replicaset group, on its master: poll mongodb_status until PRIMARY elected
  7. Per replicaset group, on its master via 127.0.0.1 localhost exception:
       create root admin user (community.mongodb.mongodb_user, no_log: true)
       create user admin
       create backup user, exporter user, mongodb_users[]

Phase 2 — lock down with keyfile + auth (rolling):
  8. Deploy keyfile to all members (content from mongodb_security_keyfile_content var, mode 0400, owner per OS)
  9. Re-render mongod.conf WITH security.keyFile AND security.authorization=enabled
 10. Rolling restart mongod (handler triggers; operator MUST use serial:1 per §5.5)
 11. Per replicaset: wait for PRIMARY re-election (mongodb_status with auth credentials)
 12. Run additional_commands (no_log) — using authenticated connection
 13. Install mongodb-exporter — using authenticated connection
```

**Recovery:** If Phase 1 step 7 fails (user create), role aborts before keyfile/auth deployed — operator debugs over open replicaset. If Phase 2 step 10 mid-restart fails, replicaset may have mixed auth state across members — operator sets `mongodb_replication_reconfigure: true` and re-runs. The role does not auto-recover from split state.

**v1.x compatibility note:** v1.x flow deployed keyfile + auth from the start and relied on localhost exception under auth. That works for fresh installs but is fragile. v2.0 splits to two phases for clarity and reliability.

### 5.5 Rolling restart contract (council #5 — strengthened)

- Default playbook usage: operator MUST use `serial: 1` (or `serial: "33%"` for large clusters) at the playbook level when this role is applied to multi-node replicaset groups. README documents this with example playbook.
- Role itself does NOT enforce `serial` directly — that's a playbook concern Ansible doesn't expose to roles.
- **Best-effort preflight check** (validate.yml): if `groups[mongodb_main_group] | length > 1` and `mongodb_allow_non_serial_apply | default(false)` is false, emit a `debug` warning recommending `serial:1`. Cannot detect actual `serial` setting from inside a role, so this is documentation/discoverability only.
- Internal handlers (`restart_mongod`, `restart_mongos`) trigger only on actual config diff (template checksum change).
- Escape hatch: `mongodb_replication_reconfigure: true` forces re-render + restart even without diff. (Note: var name is `mongodb_replication_reconfigure`, not `mongodb_reconfigure` — earlier inconsistency in this spec resolved here.)
- Hot-config changes (those that don't require restart, e.g., `setParameter` runtime adjustments) are not handled in v2.0 — out of scope.

## 6. File layout

### 6a. If Approach B (after spike pass)

```
ansible-role-mongodb/
├── meta/main.yml             # namespace: maprangzth, platforms refresh, min_ansible_version: "2.15", collections: [community.mongodb]
├── requirements.yml          # community.mongodb >=1.7,<2.0.0 (pinned major)
├── defaults/main.yml         # rewritten ~120 lines (was ~250) — clean vars, no ssl/mms/cloud, TLS schema per §6.6
├── vars/main.yml             # arch detection (apt_arch + rpm_arch + exporter_arch), see §6.5
│
├── tasks/
│   ├── main.yml              # slimmed; drop OS include, drop buster workaround, drop mms include
│   ├── install.yml           # wraps community.mongodb.mongodb_repository
│   ├── install.requirements.yml  # pymongo>=4.6, python3.9 on RHEL 8 (see §13)
│   ├── configure.yml         # branches host_group → mongod / mongos / configsvr delegation
│   ├── replicaset.yml        # community.mongodb.mongodb_replicaset + mongodb_status poll
│   ├── sharding.yml          # community.mongodb.mongodb_shard (PRESERVE — sub-project 2 modernizes)
│   ├── create_users.yml      # KEPT (uses community.mongodb.mongodb_user, no_log)
│   ├── additional_commands.yml  # KEPT (no_log: true)
│   ├── mongodb-exporter.yaml # KEPT, pinned version (see §6.7)
│   ├── validate.yml          # gatekeeper (see §8)
│   ├── disable_transparent_hugepages.yml  # KEPT — note: skipped under unprivileged docker (see §9)
│   └── uninstall.yml         # generic; mode = remove (default) | purge (opt-in via mongodb_uninstall_mode: purge)
│
├── handlers/main.yml         # restart_mongod, restart_mongos — invoked only on real diff
├── library/                  # mongodb_status_edited.py REMOVED if spike proves community.mongodb.mongodb_status works (see §4)
│                             # If spike falls back to keeping it: audit for pymongo 4.6 compat (see §13)
│
├── templates/
│   ├── mongodb.logrotate.j2  # KEPT
│   ├── mongos.logrotate.j2   # KEPT
│   ├── mongodb-exporter.service.j2  # KEPT
│   └── disable-transparent-hugepages.{debian,redhat}.service.j2  # KEPT (drop amazon)
│
├── molecule/
│   ├── debian12/             # PR-blocking — MongoDB 8.0
│   ├── rhel9/                # PR-blocking — MongoDB 8.0
│   ├── ubuntu2204/           # PR-blocking — MongoDB 8.0
│   ├── ubuntu2404/           # PR-blocking — MongoDB 8.0
│   ├── ubuntu2404-mongo70/   # PR-blocking — version sweep (Ubuntu 24.04 + MongoDB 7.0)
│   ├── ubuntu2404-mongo60/   # Nightly — deprecated tier smoke
│   ├── rhel8/                # Nightly — Python 3.9 path coverage
│   └── arm64-debian12/       # Nightly — arm64 smoke (buildx or self-hosted runner)
│
├── .github/workflows/
│   └── molecule.yml          # push + PR + schedule (daily) + workflow_dispatch
│
├── tests/                    # group_vars + hosts inventories (refresh)
├── CHANGELOG.md
├── docs/MIGRATION-v2.md      # complete var rename + removed-var table (audit from §6.6)
└── README.md
```

**Deleted under Approach B:**
- `tasks/install.{debian,redhat}.yml`, `install.requirements.{debian,redhat}.yml`, `uninstall.{debian,redhat}.yml`
- `tasks/configure_mongodb.yml`, `configure_mongos.yml`, `configure_replicaset.yml`, `create_replicaset.yml`, `configure_sharding.yml`
- `tasks/mms-agent.yml`
- `templates/mongod.conf.j2`, `mongos.conf.j2`, `mongos.service.j2`, `mongod.service.j2`, `mongos_pre.sh.j2`, `mms-agent.config.j2`, `mongodb.redhat.repo.j2`, `disable-transparent-hugepages.amazon.service.j2`
- `vars/Amazon.yml`, `Debian.yml`, `Ubuntu.yml`, `RedHat.yml`
- `molecule/default/`
- `library/mongodb_status_edited.py` (only if spike proves `community.mongodb.mongodb_status` covers — otherwise audit + keep)

### 6b. If Hybrid fallback (Approach A in v2.0)

Same layout as v1.6.5 with surgical edits:

```
ansible-role-mongodb/
├── meta/main.yml             # namespace: maprangzth, platforms refresh
├── defaults/main.yml         # ~250 → ~180 lines (drop ssl/cloud/mms, add TLS per §6.6)
├── vars/main.yml             # arch detection (apt_arch + rpm_arch + exporter_arch)
├── vars/Debian.yml           # only 6.0/7.0/8.0, codenames bookworm/jammy/noble per per-OS support table §6.4
├── vars/Ubuntu.yml           # only 6.0/7.0/8.0
├── vars/RedHat.yml           # only 6.0/7.0/8.0, $releasever 8|9
│ (Amazon.yml deleted)
│
├── tasks/                    # all existing files kept, contents refreshed
│   ├── main.yml              # drop buster workaround, drop mms include
│   ├── install.{debian,redhat}.yml  # version branches purged, codename map refreshed
│   ├── install.requirements.{debian,redhat}.yml  # pymongo 4.6+, python3.9 on RHEL 8
│   ├── uninstall.{debian,redhat}.yml  # refresh; mode = remove | purge
│   ├── configure_mongodb.yml  # drop legacy version branches in template params
│   ├── configure_mongos.yml   # drop legacy version branches
│   ├── configure_replicaset.yml  # unchanged
│   ├── configure_sharding.yml    # unchanged (preserve-not-regress)
│   ├── create_replicaset.yml     # unchanged
│   ├── create_users.yml          # no_log added throughout
│   ├── additional_commands.yml   # no_log added
│   ├── disable_transparent_hugepages.yml  # unchanged; skipped in unprivileged docker molecule
│   ├── mongodb-exporter.yaml     # pinned version + sha256 (§6.7)
│   ├── validate.yml              # gatekeeper (§8)
│   └── (mms-agent.yml DELETED)
│
├── templates/
│   ├── mongod.conf.j2        # drop ssl section, drop cloud section, drop pre-6.0 branches
│   ├── mongos.conf.j2        # drop ssl section
│   ├── (mms-agent.config.j2 DELETED)
│   ├── (disable-transparent-hugepages.amazon.service.j2 DELETED)
│   └── (rest UNCHANGED)
│
├── library/mongodb_status_edited.py  # pymongo 4.6+ compat audit + fix (REQUIRED for Hybrid path)
│
├── molecule/                 # same 8 scenarios as Approach B
├── .github/workflows/molecule.yml  # same matrix as Approach B
├── docs/ROADMAP-v3.md        # NEW — evaluation note for community.mongodb migration (not a commitment)
├── docs/MIGRATION-v2.md
├── CHANGELOG.md
└── README.md
```

### 6.3 Removed v1 variables (complete audit list)

This list must be enforced by `validate.yml` (§8). Audit performed against `defaults/main.yml`, `vars/*.yml`, `README.md`, and `tests/group_vars/` of v1.6.5:

```yaml
removed_v1_vars:
  # SSL legacy block
  - mongodb_net_ssl_enabled
  - mongodb_net_ssl_config          # nested dict — see §6.6 for replacement
  - mongodb_net_ssl_PEMKeyFile_path
  - mongodb_net_ssl_CAFile_path
  - mongodb_net_ssl_CRLFile_path
  - mongodb_net_ssl_clusterFile_path
  - mongodb_net_ssl_clusterCAFile_path
  # MMS agent
  - mongodb_mms_agent_pkg
  - mongodb_mms_group_id
  - mongodb_mms_api_key
  - mongodb_mms_base_url
  # Free cloud monitoring
  - mongodb_cloud_enabled
  - mongodb_cloud_monitoring_free_state
  # mmapv1 storage (removed in MongoDB 4.2)
  - mongodb_storage_quota_enforced
  - mongodb_storage_quota_maxfiles
  - mongodb_storage_smallfiles
  - mongodb_storage_prealloc
  # Renamed (old → new, see MIGRATION-v2.md)
  # (none in v2.0 — clean break uses new names directly)
```

`validate.yml` checks each item against `hostvars[inventory_hostname]` AND against any top-level `mongodb_net_ssl_config.*` nested keys (to catch the dict variant).

### 6.4 MongoDB × OS × architecture support matrix

Sourced from MongoDB official repository availability at https://repo.mongodb.org/ (snapshot 2026-05-22, must be re-verified during implementation):

| MongoDB | Debian 12 (bookworm) | Ubuntu 22.04 (jammy) | Ubuntu 24.04 (noble) | RHEL 8 | RHEL 9 |
|---|---|---|---|---|---|
| 6.0 | amd64+arm64 (deprecated) | amd64+arm64 (deprecated) | ❌ no official repo | amd64+arm64 (deprecated) | amd64+arm64 (deprecated) |
| 7.0 | amd64+arm64 | amd64+arm64 | amd64+arm64 | amd64+arm64 | amd64+arm64 |
| 8.0 | amd64+arm64 | amd64+arm64 | amd64+arm64 | amd64+arm64 | amd64+arm64 |

`validate.yml` asserts the (MongoDB, OS, arch) tuple is in this matrix. Combinations not listed (e.g., MongoDB 6.0 + Ubuntu 24.04) fail fast at preflight.

**Verification required during implementation:** run `curl -sI` against each repo URL combination and snapshot results into `docs/SUPPORT-MATRIX.md`. Re-verify before each release.

### 6.5 Architecture variable mapping (council #9 — fail closed)

```yaml
# vars/main.yml — fail closed, no silent default
mongodb_supported_architectures: ['x86_64', 'aarch64']

mongodb_apt_arch: "{{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture] }}"
mongodb_rpm_arch: "{{ {'x86_64': 'x86_64', 'aarch64': 'aarch64'}[ansible_architecture] }}"
mongodb_exporter_arch: "{{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture] }}"
```

`validate.yml` asserts `ansible_architecture in mongodb_supported_architectures` BEFORE these vars are referenced. Unknown architectures fail loudly at preflight, not silently into wrong repo URLs.

(`bin_arch` from v1.x removed — was conflated. Three separate vars now.)

### 6.6 TLS variable schema (council added)

Replaces the dropped `mongodb_net_ssl_config` nested dict. Flat vars in `defaults/main.yml`:

```yaml
mongodb_net_tls_enabled: false
mongodb_net_tls_mode: ""                       # disabled|allowTLS|preferTLS|requireTLS
mongodb_net_tls_certificateKeyFile: ""         # path on target — operator places file
mongodb_net_tls_CAFile: ""
mongodb_net_tls_CRLFile: ""
mongodb_net_tls_clusterFile: ""                # for inter-node auth (separate from client cert)
mongodb_net_tls_clusterCAFile: ""
mongodb_net_tls_allowConnectionsWithoutCertificates: false
mongodb_net_tls_allowInvalidCertificates: false
mongodb_net_tls_allowInvalidHostnames: false
mongodb_net_tls_FIPSMode: false
mongodb_net_tls_disabledProtocols: ""          # TLS1_0,TLS1_1,... comma-list
mongodb_net_tls_logVersions: ""                # TLS1_0,TLS1_1,... comma-list
```

`validate.yml` preflight (when `mongodb_net_tls_enabled`) — council #7 tightened:

```yaml
- name: TLS enabled but required paths empty
  ansible.builtin.assert:
    that:
      - mongodb_net_tls_certificateKeyFile | length > 0
      - mongodb_net_tls_CAFile | length > 0
      - mongodb_net_tls_mode in ['allowTLS','preferTLS','requireTLS']
    fail_msg: "mongodb_net_tls_enabled=true requires certificateKeyFile, CAFile, and a non-disabled mode."
  when: mongodb_net_tls_enabled

- name: TLS cert + key + optional files exist on target before mongod start
  ansible.builtin.stat: { path: "{{ item }}" }
  register: tls_files
  failed_when: not tls_files.stat.exists
  loop: "{{ tls_paths_to_check }}"
  vars:
    tls_paths_to_check: >-
      {{
        [mongodb_net_tls_certificateKeyFile, mongodb_net_tls_CAFile]
        + ([mongodb_net_tls_CRLFile] if mongodb_net_tls_CRLFile | length > 0 else [])
        + ([mongodb_net_tls_clusterFile] if mongodb_net_tls_clusterFile | length > 0 else [])
        + ([mongodb_net_tls_clusterCAFile] if mongodb_net_tls_clusterCAFile | length > 0 else [])
      }}
  when: mongodb_net_tls_enabled
```

**File ownership model:** Operator places `.pem` files at the configured paths out-of-band (cert lifecycle is out of role scope per §3). The role enforces correct mode (`0400`) and ownership (`mongodb_user:mongodb_group`) on those files via `ansible.builtin.file:` tasks (NOT `template:` — operator owns content, role owns permissions). Council #7 contradiction resolved.

### 6.7 mongodb-exporter pin (council added)

```yaml
# defaults/main.yml
mongodb_exporter_version: "0.42.0"   # verify latest at impl time
mongodb_exporter_sha256:
  amd64: "<sha256 from upstream release>"
  arm64: "<sha256 from upstream release>"
mongodb_exporter_link: "https://github.com/percona/mongodb_exporter/releases/download/v{{ mongodb_exporter_version }}/mongodb_exporter-{{ mongodb_exporter_version }}.linux-{{ mongodb_exporter_arch }}.tar.gz"
```

`get_url` step uses `checksum: "sha256:{{ mongodb_exporter_sha256[mongodb_exporter_arch] }}"`. CI nightly checks for upstream release drift.

## 7. Data flow

```
mongodb_version (user) → "8.0"
mongodb_major_version → "8.0"   (slice [0:3])
ansible_distribution → "Ubuntu"
ansible_distribution_release → "noble"
ansible_architecture → "aarch64"
mongodb_apt_arch → "arm64"
mongodb_rpm_arch → "aarch64"
mongodb_exporter_arch → "arm64"
        │
        ▼
(Approach A) include_vars Ubuntu.yml → mongodb_repository["8.0"] = "deb [arch={{mongodb_apt_arch}}] ..."
(Approach B) include_role community.mongodb.mongodb_repository  (handles repo+key per OS+arch)
        │
        ▼
mongodb_major_upgrade_preflight (§8) — fail if installed major ≠ target unless allow_major_upgrade
        │
        ▼
install package → configure → bootstrap auth sequence (§5.4) → users → exporter
```

## 8. Error handling and validation

### 8.1 validate.yml gatekeeper

```yaml
# Architecture preflight (council #9 — fail closed before arch vars consumed)
- name: Assert supported CPU architecture
  ansible.builtin.assert:
    that: ansible_architecture in mongodb_supported_architectures
    fail_msg: "Unsupported CPU architecture: {{ ansible_architecture }}. Allowed: {{ mongodb_supported_architectures }}"

# Major-version upgrade safety (council #2 — robust parser per council #13)
- name: Detect installed MongoDB major version
  ansible.builtin.command: mongod --version
  register: mongod_installed
  changed_when: false
  failed_when: false
  check_mode: false

- name: Parse installed major (robust — handles missing/odd output)
  ansible.builtin.set_fact:
    mongodb_installed_major: >-
      {{
        (
          (mongod_installed.stdout | default('') | regex_search('db version v(\d+\.\d+)', '\\1') | default([]))
          + ['']
        ) | first
      }}
  when: mongod_installed.rc | default(1) == 0

- name: Block accidental major-version upgrade
  ansible.builtin.fail:
    msg: |
      Installed MongoDB {{ mongodb_installed_major }} differs from target {{ mongodb_major_version }}.
      In-place major upgrades require manual step-wise procedure (see docs/MIGRATION-v2.md §upgrades).
      Set mongodb_allow_major_upgrade: true to override AFTER completing the manual upgrade.
  when:
    - mongodb_installed_major | length > 0
    - mongodb_installed_major != mongodb_major_version
    - not (mongodb_allow_major_upgrade | default(false))

# Removed v1 vars (council — complete list from §6.3)
- name: Reject removed v1 variables (clean-break enforcement)
  ansible.builtin.fail:
    msg: |
      Variable {{ item }} was removed in v2.0.0.
      See docs/MIGRATION-v2.md for the replacement.
  loop: "{{ removed_v1_vars }}"
  loop_control: { label: "{{ item }}" }
  when: lookup('vars', item, default=None) is not none

# Nested SSL config dict (catches mongodb_net_ssl_config.mode, etc.)
- name: Reject legacy SSL config dict
  ansible.builtin.fail:
    msg: "mongodb_net_ssl_config removed in v2.0. Use mongodb_net_tls_* flat vars per docs/MIGRATION-v2.md."
  when: mongodb_net_ssl_config is defined and (mongodb_net_ssl_config | length > 0)

# Version validation by major (council #15)
- name: Assert MongoDB major version is supported
  ansible.builtin.assert:
    that: mongodb_major_version in ['6.0', '7.0', '8.0']
    fail_msg: "Unsupported MongoDB major: {{ mongodb_major_version }}. Allowed: 6.0 (deprecated), 7.0, 8.0"

- name: Require explicit opt-in for deprecated 6.0
  ansible.builtin.fail:
    msg: |
      MongoDB 6.0 reached end of life on 2025-07-31 — no security patches from MongoDB.
      To proceed anyway, set mongodb_allow_eol_version: true.
  when:
    - mongodb_major_version == "6.0"
    - not (mongodb_allow_eol_version | default(false))

- name: Warn when using EOL MongoDB 6.0
  ansible.builtin.debug:
    msg: "⚠️  MongoDB 6.0 is end-of-life. Plan migration to 7.0 or 8.0."
  when: mongodb_major_version == "6.0"

# Support matrix (council #3)
- name: Assert (MongoDB, OS, arch) combination is supported
  ansible.builtin.assert:
    that: >-
      mongodb_major_version in mongodb_support_matrix and
      ansible_distribution in mongodb_support_matrix[mongodb_major_version] and
      ansible_distribution_major_version in mongodb_support_matrix[mongodb_major_version][ansible_distribution] and
      ansible_architecture in mongodb_support_matrix[mongodb_major_version][ansible_distribution][ansible_distribution_major_version]
    fail_msg: |
      Unsupported combination: MongoDB {{ mongodb_major_version }} on
      {{ ansible_distribution }} {{ ansible_distribution_major_version }} ({{ ansible_architecture }}).
      See docs/SUPPORT-MATRIX.md.

# PyMongo version (uses ansible_python_interpreter, not bare python3)
- name: Assert pymongo >= 4.6 using configured interpreter
  ansible.builtin.command: >
    {{ ansible_python_interpreter | default('/usr/bin/python3') }} -c
    "from packaging.version import Version; import pymongo; assert Version(pymongo.__version__) >= Version('4.6')"
  changed_when: false
  # Run only on hosts that will execute community.mongodb modules (replicaset masters)
  when: inventory_hostname in (mongodb_replicaset_masters | default({}) | dict2items | map(attribute='value') | list)

# x86-64-v2 microarchitecture (council #8 — fail closed + cross-platform path)
- name: Locate ld.so cross-platform
  ansible.builtin.stat:
    path: "{{ item }}"
  loop:
    - /lib64/ld-linux-x86-64.so.2                       # RHEL/Rocky/Alma
    - /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2        # Debian/Ubuntu
  register: ldso_probe
  when: ansible_architecture == "x86_64" and mongodb_major_version in ['7.0', '8.0']

- name: Set ld.so path
  ansible.builtin.set_fact:
    ldso_path: "{{ (ldso_probe.results | selectattr('stat.exists', 'equalto', true) | map(attribute='item') | list + [''])[0] }}"
  when: ansible_architecture == "x86_64" and mongodb_major_version in ['7.0', '8.0']

- name: Check x86-64-v2 microarchitecture
  ansible.builtin.command: "{{ ldso_path }} --help"
  register: ld_help
  changed_when: false
  failed_when: false
  when:
    - ansible_architecture == "x86_64"
    - mongodb_major_version in ['7.0', '8.0']
    - ldso_path | length > 0

- name: Assert x86-64-v2 supported (MongoDB 7.0+ on x86_64) — fail closed
  ansible.builtin.assert:
    that:
      - ldso_path | length > 0
      - ld_help.rc | default(1) == 0
      - "'x86-64-v2 (supported' in (ld_help.stdout | default(''))"
    fail_msg: |
      MongoDB {{ mongodb_major_version }} requires x86-64-v2 microarchitecture.
      Either: CPU does not support it, ld.so could not be located, or ld.so output format
      changed (path={{ ldso_path | default('not found') }}). Fix infra or run on x86-64-v2 CPU.
  when:
    - ansible_architecture == "x86_64"
    - mongodb_major_version in ['7.0', '8.0']

# FCV auto-bump prevention (council removed undefined vars)
- name: Confirm role does not auto-set FCV
  ansible.builtin.debug:
    msg: |
      ℹ️  This role does NOT call setFeatureCompatibilityVersion().
          After upgrading MongoDB major version, run manually:
            db.adminCommand({setFeatureCompatibilityVersion: "{{ mongodb_major_version }}", confirm: true})
  when: mongodb_allow_major_upgrade | default(false)
```

### 8.2 Secret handling (council #10)

Every task touching passwords, keyfile content, TLS private keys: `no_log: true`. Sample:

```yaml
- name: Deploy keyfile
  ansible.builtin.copy:
    content: "{{ mongodb_security_keyfile_content }}"
    dest: "{{ mongodb_security_keyfile_path }}"
    owner: "{{ mongodb_user }}"
    group: "{{ mongodb_group }}"
    mode: "0400"
  no_log: true

- name: Create root admin user
  community.mongodb.mongodb_user:
    login_user: ""
    login_password: ""
    database: admin
    name: "{{ mongodb_root_admin_name }}"
    password: "{{ mongodb_root_admin_password }}"
    roles: [ root ]
    state: present
  no_log: true
  delegate_to: "{{ mongodb_master_host }}"
  run_once: true
```

### 8.3 Other error paths

| Error | Behavior |
|---|---|
| Repo key fetch fail | retry 3x, delay 10s, then fail |
| Package not found for combo | caught by §8.1 support matrix preflight before install |
| mongod start fail | systemd fail → capture `journalctl -u mongod --no-pager -n 100` → fail with output |
| Replicaset partial init | `mongodb_replication_reconfigure: true` → re-run reconciles |
| TLS cert missing on target | §6.6 preflight fails before mongod restart |
| Auth lockout on failed user create in Phase 2 | role aborts before authorization enabled (see §5.4 Phase 2) |
| Idempotency violation | molecule idempotence phase catches; CI fails |

## 9. Testing

### 9.1 Test matrix (8 scenarios — authoritative, council #11 cleanup)

| Scenario dir | OS | MongoDB | Trigger |
|---|---|---|---|
| `molecule/debian12/` | Debian 12 (bookworm) | 8.0 | PR-blocking |
| `molecule/rhel9/` | Rocky 9 | 8.0 | PR-blocking |
| `molecule/ubuntu2204/` | Ubuntu 22.04 (jammy) | 8.0 | PR-blocking |
| `molecule/ubuntu2404/` | Ubuntu 24.04 (noble) | 8.0 | PR-blocking |
| `molecule/ubuntu2404-mongo70/` | Ubuntu 24.04 | 7.0 | PR-blocking (version sweep) |
| `molecule/debian12-mongo60/` | Debian 12 | 6.0 | Nightly only (deprecated tier, `mongodb_allow_eol_version: true` set in converge; valid combo per §6.4) |
| `molecule/rhel8/` | Rocky 8 | 8.0 | Nightly only (Python 3.9 install path) |
| `molecule/arm64-debian12/` | Debian 12 arm64 | 8.0 | Nightly only (buildx or self-hosted runner) |

### 9.2 Per-scenario molecule layout

```yaml
# molecule/<scenario>/molecule.yml
platforms:
  - &node
    image: "<base>"
    privileged: true              # required for systemd + disable_thp
    capabilities: [SYS_ADMIN]
    cgroupns_mode: host
    cgroup_parent: docker.slice
    tmpfs: [/run, /run/lock, /tmp]
    security_opts: [seccomp=unconfined]
    name: mongo01
    groups: [mongo_cluster]
  - <<: *node
    name: mongo02
  - <<: *node
    name: mongo03
```

Privileged + SYS_ADMIN + cgroup mounts are required because the role installs systemd units, manages `mongod.service`, and runs `disable_transparent_hugepages`. Without these, tests fail at service start or THP step.

### 9.3 disable_thp under Docker (council #22)

In each scenario's `prepare.yml`:

```yaml
- name: Skip THP disable in unprivileged molecule runs
  ansible.builtin.set_fact:
    mongodb_disable_transparent_hugepages: "{{ false if (ansible_virtualization_type | default('') == 'docker' and not (lookup('env', 'MOLECULE_PRIVILEGED') | default(true) | bool)) else true }}"
```

Privileged molecule scenarios (default) attempt THP disable. Unprivileged variant (if added) skips THP. Document caveat in README.

### 9.4 verify.yml (per scenario)

```yaml
- name: mongod service active
  ansible.builtin.systemd: { name: mongod }
  register: svc
- assert: { that: "svc.status.ActiveState == 'active'" }

- name: port 27017 listening
  ansible.builtin.wait_for: { port: 27017, timeout: 5 }

- name: mongod version matches expected
  ansible.builtin.command: mongod --version
  register: ver
  changed_when: false
- assert:
    that: "'db version v' + mongodb_major_version in ver.stdout"

- name: replicaset healthy (auth-aware, council #14)
  community.mongodb.mongodb_status:
    replica_set: rs01
    poll: 6
    interval: 5
    login_user: "{{ mongodb_root_admin_name }}"
    login_password: "{{ mongodb_root_admin_password }}"
    login_database: admin
    login_host: 127.0.0.1
  no_log: true
  register: rs
- assert: { that: "rs.replicaset is mapping" }

- name: anon connection rejected
  ansible.builtin.command: mongosh --quiet --eval "db.adminCommand('listDatabases')"
  register: anon
  failed_when: anon.rc == 0
  changed_when: false

- name: admin auth works
  community.mongodb.mongodb_shell:
    login_user: "{{ mongodb_root_admin_name }}"
    login_password: "{{ mongodb_root_admin_password }}"
    eval: "db.runCommand({ping:1})"
  no_log: true
  register: ping
- assert: { that: "ping.transformed_output.ok == 1" }

- name: keyfile perms
  ansible.builtin.stat: { path: "{{ mongodb_security_keyfile_path }}" }
  register: kf
- assert:
    that:
      - kf.stat.mode == "0400"
      - kf.stat.pw_name == mongodb_user

- name: exporter listening
  ansible.builtin.wait_for: { port: 9216, timeout: 5 }
  when: mongodb_exporter_enabled
```

Idempotence is asserted via molecule's built-in `idempotence` phase (second converge → 0 changed tasks), not in verify.yml.

### 9.5 Lint

```yaml
# .ansible-lint
profile: production
exclude_paths: [molecule/, tests/]
# No skip_list — clean break means clean lint
```

```yaml
# .yamllint
extends: default
rules:
  line-length: { max: 160 }
  truthy: { allowed-values: ["true", "false"] }
```

### 9.6 GitHub Actions workflow (council #11 fixed)

```yaml
name: molecule
on:
  push:
  pull_request:
  schedule:
    - cron: "0 3 * * *"          # daily 03:00 UTC
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install ansible-core ansible-lint yamllint
      - run: ansible-lint
      - run: yamllint .

  molecule-pr:
    needs: lint
    if: github.event_name != 'schedule'
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        scenario: [debian12, rhel9, ubuntu2204, ubuntu2404, ubuntu2404-mongo70]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install ansible-core molecule molecule-plugins[docker] docker pymongo
      - run: ansible-galaxy collection install -r requirements.yml
      - run: molecule test -s ${{ matrix.scenario }}

  molecule-nightly:
    needs: lint
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        scenario: [debian12-mongo60, rhel8, arm64-debian12]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - name: Setup QEMU (for arm64 scenario)
        if: matrix.scenario == 'arm64-debian12'
        uses: docker/setup-qemu-action@v3
      - run: pip install ansible-core molecule molecule-plugins[docker] docker pymongo
      - run: ansible-galaxy collection install -r requirements.yml
      - run: molecule test -s ${{ matrix.scenario }}
```

### 9.7 Pre-release smoke checklist (manual, before tagging v2.0.0)

- [ ] All PR-blocking scenarios green in CI for 5 consecutive runs
- [ ] Latest nightly run green
- [ ] `ansible-lint` + `yamllint .` clean
- [ ] Manual deploy to staging shard cluster (`tests/hosts-shards`) — verifies sharding preserve-not-regress
- [ ] Manual upgrade from v1.6.5 → v2.0.0 on disposable VM: every removed v1 var triggers fail-fast, no package mass-upgrade
- [ ] Manual arm64 deploy on Apple Silicon or AWS Graviton (1 standalone node, 1 replicaset member)
- [ ] `docs/MIGRATION-v2.md` migration table covers every renamed and removed var (cross-checked against §6.3)
- [ ] B-spike report (if Approach B chosen) checked in
- [ ] CHANGELOG.md v2.0.0 entry written
- [ ] `docs/SUPPORT-MATRIX.md` snapshot fresh

## 10. Migration impact on users

Users upgrading from v1.x must:

1. Change role source: `superset1.mongodb` → `maprangzth.mongodb`
2. Bump version pin: `v1.6.5` → `v2.0.0`
3. Pin `mongodb_version` explicitly in `group_vars/` — do NOT rely on default. Default changed from `4.4` to `8.0`.
4. Read `docs/MIGRATION-v2.md` and apply var renames + removals (audited list per §6.3)
5. If on MongoDB ≤ 5.0: upgrade the database **manually** step-wise before applying the role:
   - `4.4 → 5.0` (set FCV 5.0) → `5.0 → 6.0` (set FCV 6.0) → `6.0 → 7.0` (set FCV 7.0) → `7.0 → 8.0` (set FCV 8.0)
   - MongoDB engine **does not support skipping major versions**. Skipping causes startup refusal.
6. If on Amazon Linux: switch to RHEL / Rocky / AlmaLinux or stay on v1.x
7. If using `mongodb_net_ssl_*` vars: migrate to `mongodb_net_tls_*` per §6.6 flat schema
8. If using MMS agent: deploy MMS separately (out of role scope) or move to MongoDB Atlas
9. If using `mongodb_cloud_*` free monitoring: feature deprecated upstream; no v2.0 replacement
10. If on Debian 11 or Ubuntu 20.04: pin to v1.x branch or upgrade OS first
11. If on RHEL 8: install `python3.9` package via `dnf install python3.9` and set `ansible_python_interpreter: /usr/bin/python3.9` in inventory `group_vars/`. **Do not use `/usr/libexec/platform-python`** — it is Python 3.6 and incompatible with PyMongo 4.6+. The role's `install.requirements` task on RHEL 8 will install python3.9, but operators must set `ansible_python_interpreter` themselves for Ansible to find it. README provides example.

### 10.1 Galaxy / installation path (council #18)

- During RC phase: install via git URL only — `ansible-galaxy install git+https://github.com/maprangzth/ansible-role-mongodb,v2.0.0-rc1`
- At GA: publish to Galaxy as `maprangzth.mongodb` v2.0.0 — `ansible-galaxy install maprangzth.mongodb,v2.0.0`
- Both paths documented in README

## 11. Repo + branch strategy

```
maprangzth/ansible-role-mongodb
├── main           ← default branch (was `master`, renamed via GitHub UI). Tracks v2.x.
├── master         ← legacy pointer. Points to v1.x HEAD (NOT main). Kept for 1 release after v2.0.0 GA.
├── v1.x           ← cut from commit 6276c10 (v1.6.5), security backports only. `master` mirrors this.
└── spike/community-mongodb-eval  ← short-lived B-spike branch
```

**Branch rename strategy (council #18 — corrected):**
- After GitHub rename `master` → `main`, immediately re-create `master` as a pointer to `v1.x` HEAD (NOT to `main`). Existing `git+https://...` installs targeting `master` will continue resolving to v1.x, protecting v1 users from accidental v2 upgrade.
- README header announces: "`master` branch is now v1.x maintenance. New work lives on `main`. Pin your installs to a tag (e.g. `v2.0.0`) instead of a branch."
- After v2.1.0 release: delete `master` branch entirely. By that point, GitHub's 90-day auto-redirect window has closed and users have had time to migrate to tag-pinned installs.
- This means `git+https://github.com/maprangzth/ansible-role-mongodb,master` resolves to v1.x for ~1 release, then errors. Documented explicitly in CHANGELOG and README.

**Implementation order:**

1. Cut `v1.x` branch from current HEAD (`6276c10`) on current `master`
2. Pre-spike verification (§4) of `community.mongodb` collection
3. Open `spike/community-mongodb-eval` and run 3-day B-spike
4. Write spike report → decide Approach B or fall back Hybrid
5. Rename `master` → `main` via GitHub Settings → Branches (after decision)
6. Implementation PRs land on `refactor/v2.0-foundation`
7. CI green → merge to `main`
8. Tag `v2.0.0-rc1`, dogfood for 1 week
9. If RC clean: tag `v2.0.0`, write GitHub Release
10. Publish to Galaxy as `maprangzth.mongodb`
11. v2.1.0 (later): delete legacy `master` pointer branch

**Branch protection:**
- `main`: require PR, require CI pass, allow self-merge (solo maintainer)
- `v1.x`: protected, security backports only — scope = CVE fixes in dependencies (pymongo, ansible modules) AND repository key rotations only; no feature work, no OS additions, no MongoDB version additions

**License + attribution:**
- Keep MIT license
- `meta/main.yml`: `namespace: maprangzth`, `author: maprangzth (forked from Vitaly Kargin / superset1)`
- README header note: "Fork of `superset1/ansible-role-mongodb` (unmaintained since 2023). Diverged at v1.6.5."

## 12. Sharding scope clarification (council #13)

v2.0 = **preserve-not-regress**:
- Existing `configure_sharding.yml` and `configure_mongos.yml` (or Approach B equivalent) keep working
- Spike flow #4 (sharded cluster setup) gates that this works under chosen approach
- Tests: at minimum, manual smoke (`tests/hosts-shards`); ideally one nightly molecule scenario added (deferred to sub-project 2 if molecule sharding scenario is too heavy)
- No new sharding features in v2.0

v2.x sub-project 2 = sharding modernization:
- config-shard support (new in MongoDB 7.0 — a configsvr can also host data)
- balancer mgmt tasks
- improved idempotency on shard add/remove
- molecule sharding scenario

## 13. Required implementation tasks (promoted from open issues)

| Task | Why |
|---|---|
| RHEL 8 Python 3.9 install + `ansible_python_interpreter` documentation + molecule rhel8 scenario | Council #6 — system Python 3.6 blocks PyMongo 4.6 |
| `library/mongodb_status_edited.py` PyMongo 4.6+ audit | Required for Hybrid path; required for Approach B if spike doesn't replace it |
| OS-specific user/group/service mapping survives despite vars/*.yml deletion in Approach B | Keep `mongodb_user`/`mongodb_group` derivation in `defaults/main.yml` using `ansible_os_family` ternary (same as v1.x). community.mongodb.mongodb_mongod role inherits these vars when passed. Verify in spike. |
| Verify `community.mongodb` collection roles exist with assumed names + capabilities | Pre-spike step §4 |
| Snapshot MongoDB × OS × arch repo availability into `docs/SUPPORT-MATRIX.md` | Reproducibility, council #14 |
| Audit complete removed-var list from v1.x defaults/vars/README/tests | §6.3 — clean break enforcement must catch every var |
| Pin `mongodb_exporter_version` + sha256 per arch | Council #20 |
| Add x86-64-v2 check (replaces simple AVX grep) | Council #17 — MongoDB 7.0+ requires |

## 14. Open issues (true unknowns, resolve during implementation)

| Issue | Resolution path |
|---|---|
| arm64 CI runner availability — buildx vs self-hosted | Decide during impl: buildx with QEMU is slow but free; self-hosted requires hardware. Start with buildx, escalate if too slow. |
| MongoDB 8.0 upstream version drift during impl | Pin to current 8.0.x point release in tests; CI nightly can detect new minors |
| `community.mongodb` collection bug surfacing during spike | Document workaround in spike report; potentially block decision pending upstream fix |
| Whether `mongodb_status_edited.py` survives in Approach B | Decided at spike time — flow #3 evidence determines |

## 15. Reference material consulted

- endoflife.date for MongoDB, RHEL, Ubuntu, Debian (queried 2026-05-22)
- Context7 `/mongodb/docs` for install repo paths, sharding setup, backup methods
- Context7 `/ansible-collections/community.mongodb` for role/module surface
- Council fan-out #1 (OpenAI GPT-5.5 + Google Gemini 3.1 Pro): approach decision
- Council fan-out #2 (same models): spec review → drove this v1.0 revision

---
