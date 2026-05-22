# 2026-05-22 — ansible-role-mongodb v2.0.0 Foundation Refactor

**Status:** Design / pending implementation plan
**Owner:** maprangzth
**Repo:** [maprangzth/ansible-role-mongodb](https://github.com/maprangzth/ansible-role-mongodb) (hard fork of `superset1/ansible-role-mongodb`, unmaintained since 2023)
**Spec scope:** Sub-project 1 only — version + OS matrix refactor. Sub-projects 2 (sharding modernization) and 3 (backup feature) get separate specs after v2.0.0 ships.

---

## 1. Goal

Modernize the role so it cleanly supports MongoDB 7.0 + 8.0 on currently-released RHEL / Debian / Ubuntu LTS targets, drop ~9 years of legacy support code (MongoDB 3.4–5.0, SSL legacy block, MMS agent, Amazon Linux), and rebuild test + CI infrastructure. Ship as `maprangzth.mongodb` v2.0.0 — a clean break with no backward-compatibility shim layer.

## 2. Decision summary

| Question | Decision |
|---|---|
| Release shape | v2.0.0 clean break, no var shim |
| MongoDB versions supported | 8.0 (default, LTS until Oct 2029), 7.0 (LTS until Aug 2027), 6.0 (deprecated tier — warning emitted, no new features) |
| MongoDB versions dropped | 3.4, 3.6, 4.0, 4.2, 4.4, 5.0 |
| Default `mongodb_version` | `"8.0"` |
| OS — Primary support | Debian 12, Ubuntu 22.04 + 24.04, RHEL 8 + 9 (incl. Rocky/AlmaLinux) |
| OS — Dropped | Amazon Linux (all), Debian ≤ 10, Ubuntu ≤ 20.04, RHEL ≤ 7 |
| OS — Out of scope for v2.0 | Debian 11 (EOL Aug 2026), Debian 13, Ubuntu 26.04, RHEL 10 — add as MongoDB publishes official repos |
| Architecture | amd64 + arm64 (detect at runtime) |
| Features dropped | `mongodb_net_ssl_config` legacy block (TLS-only henceforth), MMS agent + `mongodb_cloud_*` vars, MongoDB free cloud monitoring config section |
| Features kept | mongodb-exporter (bump 0.37.0 → latest), keyfile auth, TLS cluster file, replicaset poll lib, logrotate, disable_thp, custom roles, custom users |
| Approach (architectural shift) | **B-spike → decide** (see §4) |
| Dependency floor | `ansible-core >= 2.15`, `pymongo >= 4.6`, `python >= 3.9`, `community.mongodb >= 1.7` (if Approach B chosen) |
| CI | GitHub Actions, sparse 2D molecule matrix |
| Repo strategy | Hard fork, rename `master` → `main`, branch `v1.x` for security backports, namespace `maprangzth` |

## 3. Non-goals

- In-place data upgrade across MongoDB major versions (4.4 → 8.0) — operator runs the MongoDB upgrade procedure manually before applying the role.
- TLS cert lifecycle / PKI — operator provides `.pem` files; role only places them.
- Backup orchestration — separate sub-project, separate spec.
- Sharding flow modernization (config-shard, etc.) — separate sub-project.
- Performance benchmarking vs v1.x.

## 4. Architectural decision: B-spike → Approach B or Hybrid

Two viable approaches considered, plus a 3-day spike gate.

### Approach A — Strip-and-modernize in-place
Keep current task structure. Surgically delete legacy code paths. Own templates and per-OS vars. Lower implementation risk, higher long-term maintenance.

### Approach B — Delegate to `community.mongodb`
Replace install / configure / replicaset / sharding tasks with calls into the upstream `community.mongodb` collection's roles + modules. Keep value-add (user mgmt, exporter, logrotate, mongodb_status poll). Higher implementation risk, lower long-term maintenance.

### Decision gate: 3-day B-spike before committing

Before locking the approach, run a time-boxed 3-day prototype of Approach B against the four highest-risk flows:

1. **TLS cluster certificate** (separate `clusterFile` from `certificateKeyFile`)
2. **Keyfile auth** lifecycle (content set via var, deployed identically across members, 0400 perms)
3. **3-node replicaset init** via `community.mongodb.mongodb_replicaset` + status convergence poll
4. **Sharded cluster setup** (configsvr replicaset + 2 shards + mongos)

**Pass criteria (all must hold):**
- All four flows work end-to-end against a real MongoDB 8.0 deployment.
- Each flow's custom wrapper code (anything outside `include_role` + var passing) stays under 50 LOC.
- Total custom code added across all four flows stays under 200 LOC.
- No upstream template override required (i.e., we do not have to fork `community.mongodb`'s `mongod.conf.j2` or `mongos.conf.j2`).
- Idempotency: rerun produces zero changed tasks.

**Decision rule:**
- ✅ All pass criteria hold → commit Approach B for v2.0.0.
- ❌ Any criterion fails → fall back to **Hybrid**: ship Approach A for v2.0.0 + record a "v3 evaluation roadmap" in `docs/ROADMAP-v3.md` (note: roadmap is an evaluation note, not a commitment).

Rationale: council fan-out (GPT-5.5 + Gemini 3.1 Pro) split on this — Gemini argued users should be broken once, not twice; GPT argued blind migration to upstream is risky given custom flow depth. Spike resolves the disagreement empirically.

### Spike deliverables (3 days)

- Branch: `spike/community-mongodb-eval`
- `tests/spike-inventory/` with single configsvr + 2 shard + 1 mongos host group
- Markdown report: `docs/superpowers/specs/2026-05-22-spike-report.md` covering each of the 4 flows: works / works with workaround / blocked. Quote upstream var names used.
- Decision recorded in same spec doc: commit B or fall back Hybrid.

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
  3. set_fact mongodb_master
  4. include_tasks install.requirements (pymongo, python deps)
  5. include_tasks validate.yml  (assertion gate)
  6. include_tasks install (apt/yum repo + pkg) | delegate
  7. branch on group:
       data nodes  → configure_mongodb.yml | community.mongodb.mongodb_mongod
       configsvr   → configure_mongodb.yml --configsvr | community.mongodb.mongodb_config
       mongos      → configure_mongos.yml  | community.mongodb.mongodb_mongos
  8. replicaset init (master host only) — community.mongodb.mongodb_replicaset + library/mongodb_status_edited.py poll
  9. sharding (mongos master only) — community.mongodb.mongodb_shard
 10. create_users.yml (master only) — kept identical, uses community.mongodb.mongodb_user
 11. additional_commands.yml (opt-in via tag)
 12. mongodb-exporter.yaml (if enabled)
```

## 6. File layout

### 6a. If Approach B (after spike pass)

```
ansible-role-mongodb/
├── meta/main.yml             # namespace: maprangzth, platforms refresh, min_ansible_version: "2.15"
├── requirements.yml          # NEW — pinned community.mongodb >=1.7,<2.0.0
├── defaults/main.yml         # rewritten ~120 lines (was ~250) — clean vars, no ssl/mms/cloud
├── vars/main.yml             # + bin_arch detect (amd64/arm64)
│
├── tasks/
│   ├── main.yml              # slimmed; drop OS include, drop buster workaround, drop mms include
│   ├── install.yml           # wraps community.mongodb.mongodb_repository
│   ├── install.requirements.yml  # pymongo>=4.6, python3-pip
│   ├── configure.yml         # branches host_group → mongod / mongos / configsvr delegation
│   ├── replicaset.yml        # community.mongodb.mongodb_replicaset + status poll
│   ├── sharding.yml          # community.mongodb.mongodb_shard
│   ├── create_users.yml      # KEPT (uses community.mongodb.mongodb_user)
│   ├── additional_commands.yml  # KEPT
│   ├── mongodb-exporter.yaml # KEPT, bump exporter version
│   ├── validate.yml          # slimmed — drop pre-6.0 version checks, add v1-var-removed fails
│   ├── disable_transparent_hugepages.yml  # KEPT
│   └── uninstall.yml         # generic, OS-detect via package module
│
├── handlers/main.yml         # KEPT
├── library/mongodb_status_edited.py  # pymongo 4.6+ compatibility audit + fix
│
├── templates/
│   ├── mongodb.logrotate.j2  # KEPT
│   ├── mongos.logrotate.j2   # KEPT
│   ├── mongodb-exporter.service.j2  # KEPT
│   └── disable-transparent-hugepages.{debian,redhat}.service.j2  # KEPT (drop amazon)
│
├── molecule/
│   ├── debian12/
│   ├── rhel9/
│   ├── ubuntu2204/
│   └── ubuntu2404/
│
├── .github/workflows/
│   └── molecule.yml          # sparse 2D matrix
│
├── tests/                    # group_vars + hosts inventories (refresh)
├── CHANGELOG.md
├── docs/MIGRATION-v2.md      # var rename table, removed-var list
└── README.md
```

**Deleted under Approach B:**
- `tasks/install.{debian,redhat}.yml`, `install.requirements.{debian,redhat}.yml`, `uninstall.{debian,redhat}.yml`
- `tasks/configure_mongodb.yml`, `configure_mongos.yml`, `configure_replicaset.yml`, `create_replicaset.yml`, `configure_sharding.yml`
- `tasks/mms-agent.yml`
- `templates/mongod.conf.j2`, `mongos.conf.j2`, `mongos.service.j2`, `mongod.service.j2`, `mongos_pre.sh.j2`, `mms-agent.config.j2`, `mongodb.redhat.repo.j2`, `disable-transparent-hugepages.amazon.service.j2`
- `vars/Amazon.yml`, `Debian.yml`, `Ubuntu.yml`, `RedHat.yml`
- `molecule/default/`

### 6b. If Hybrid fallback (Approach A in v2.0)

```
ansible-role-mongodb/
├── meta/main.yml             # namespace: maprangzth, platforms refresh
├── defaults/main.yml         # ~250 → ~180 lines (drop ssl/cloud/mms)
├── vars/main.yml             # + bin_arch detect
├── vars/Debian.yml           # only 6.0/7.0/8.0, codenames bookworm/jammy/noble
├── vars/Ubuntu.yml           # only 6.0/7.0/8.0
├── vars/RedHat.yml           # only 6.0/7.0/8.0, $releasever 8|9
│ (Amazon.yml deleted)
│
├── tasks/                    # all existing files kept, contents refreshed
│   ├── main.yml              # drop buster workaround, drop mms include
│   ├── install.{debian,redhat}.yml  # version branches purged, codename map refreshed
│   ├── install.requirements.{debian,redhat}.yml  # pymongo 4.6+
│   ├── uninstall.{debian,redhat}.yml  # refresh
│   ├── configure_mongodb.yml  # drop legacy version branches in template params
│   ├── configure_mongos.yml   # drop legacy version branches
│   ├── configure_replicaset.yml  # unchanged
│   ├── configure_sharding.yml    # unchanged
│   ├── create_replicaset.yml     # unchanged
│   ├── create_users.yml          # unchanged
│   ├── additional_commands.yml   # unchanged
│   ├── disable_transparent_hugepages.yml  # unchanged
│   ├── mongodb-exporter.yaml     # bump version
│   ├── validate.yml              # drop pre-6.0 checks, add v1-var-removed fails
│   └── (mms-agent.yml DELETED)
│
├── templates/
│   ├── mongod.conf.j2        # drop ssl section, drop cloud section, drop pre-6.0 branches
│   ├── mongos.conf.j2        # drop ssl section
│   ├── (mms-agent.config.j2 DELETED)
│   ├── (disable-transparent-hugepages.amazon.service.j2 DELETED)
│   └── (rest UNCHANGED)
│
├── library/mongodb_status_edited.py  # pymongo 4.6+ audit
│
├── molecule/                 # same as Approach B
│   ├── debian12/
│   ├── rhel9/
│   ├── ubuntu2204/
│   └── ubuntu2404/
│
├── .github/workflows/molecule.yml  # same matrix
├── docs/ROADMAP-v3.md        # NEW — evaluation note for community.mongodb migration
├── docs/MIGRATION-v2.md
├── CHANGELOG.md
└── README.md
```

## 7. Data flow

(Unchanged from v1.x at the inventory contract. Internal flow differs per approach — see §5 architecture.)

```
mongodb_version (user) → "8.0"
mongodb_major_version → "8.0"
ansible_distribution → "Ubuntu"
ansible_distribution_release → "noble"
ansible_architecture → "aarch64"
bin_arch → "arm64"   (NEW, derived in vars/main.yml)
        │
        ▼
(Approach A) include_vars Ubuntu.yml → mongodb_repository["8.0"] = "deb [arch={{bin_arch}}] ..."
(Approach B) include_role community.mongodb.mongodb_repository  (handles repo+key per OS+arch)
```

## 8. Error handling and validation

`tasks/validate.yml` becomes the gatekeeper. New assertions / explicit fail blocks (council-driven addition):

```yaml
- name: Reject removed v1 variables (clean-break enforcement)
  ansible.builtin.fail:
    msg: |
      Variable {{ item }} was removed in v2.0.0.
      See docs/MIGRATION-v2.md for the replacement.
  when: hostvars[inventory_hostname][item] is defined
  loop:
    - mongodb_net_ssl_enabled
    - mongodb_net_ssl_config
    - mongodb_mms_api_key
    - mongodb_mms_group_id
    - mongodb_mms_base_url
    - mongodb_cloud_enabled
    - mongodb_cloud_monitoring_free_state
  loop_control: { label: "{{ item }}" }

- name: Assert MongoDB version is supported
  ansible.builtin.assert:
    that: mongodb_version in ['6.0', '7.0', '8.0']
    fail_msg: "Unsupported mongodb_version. Allowed: 6.0 (deprecated), 7.0, 8.0"

- name: Warn when using deprecated MongoDB 6.0
  ansible.builtin.debug:
    msg: |
      ⚠️  MongoDB 6.0 reached end of life on 2025-07-31.
          No security patches from MongoDB. Plan migration to 7.0 or 8.0.
  when: mongodb_version == "6.0"

- name: Assert supported OS combination
  ansible.builtin.assert:
    that: >
      (ansible_distribution == "Debian" and ansible_distribution_major_version == "12") or
      (ansible_distribution == "Ubuntu" and ansible_distribution_version in ["22.04", "24.04"]) or
      (ansible_os_family == "RedHat" and ansible_distribution_major_version in ["8", "9"])
    fail_msg: "Unsupported OS. See README for primary support matrix."

- name: Assert pymongo >= 4.6
  ansible.builtin.command: python3 -c "import pymongo; assert tuple(int(x) for x in pymongo.__version__.split('.')[:2]) >= (4,6)"
  changed_when: false
  when: mongodb_master | default(false)

- name: Assert no FCV auto-bump intent
  ansible.builtin.assert:
    that: not (mongodb_force_install and mongodb_set_fcv | default(false))
    fail_msg: "v2.0 does not auto-set featureCompatibilityVersion. Run setFeatureCompatibilityVersion() manually after upgrade."
```

**Other error paths:** same as documented in design conversation (install retry, replicaset poll timeout, sharding idempotency check, keyfile perms enforcement).

## 9. Testing

### Sparse 2D test matrix (council-driven)

| Scenario | OS | MongoDB | When |
|---|---|---|---|
| `debian12` | Debian 12 | 8.0 | PR blocking |
| `rhel9` | Rocky 9 | 8.0 | PR blocking |
| `ubuntu2204` | Ubuntu 22.04 | 8.0 | PR blocking |
| `ubuntu2404` | Ubuntu 24.04 | 8.0 | PR blocking |
| `ubuntu2404-mongo70` | Ubuntu 24.04 | 7.0 | PR blocking |
| `ubuntu2404-mongo60` | Ubuntu 24.04 | 6.0 | Nightly (deprecated tier smoke) |
| `rhel8` | Rocky 8 | 8.0 | Nightly |
| `arm64-debian12` | Debian 12 arm64 | 8.0 | Nightly (self-hosted runner or buildx) |

### Per-scenario molecule layout

```
molecule/<scenario>/
├── molecule.yml      # platforms: 3x base image, docker_networks, capabilities
├── Dockerfile.j2     # systemd-enabled base
├── prepare.yml       # apt/yum update, install systemd, python3-pip
├── converge.yml      # apply role with replicaset cfg
└── verify.yml        # service active, port 27017 listening, replicaset healthy,
                      #   auth required (anon rejected), keyfile 0400 + correct owner,
                      #   exporter port 9216 listening, idempotence (changed_when False on rerun)
```

### Lint

- `ansible-lint` profile production, skip `role-name` + `var-naming[no-role-prefix]`
- `yamllint` extends default, line-length max 160

### GitHub Actions workflow

```yaml
name: molecule
on: [push, pull_request]
jobs:
  lint: { ... }            # ansible-lint + yamllint
  molecule:
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        scenario: [debian12, rhel9, ubuntu2204, ubuntu2404, ubuntu2404-mongo70]
    steps: [ ... ]
  nightly:
    if: github.event_name == 'schedule'
    strategy:
      matrix:
        scenario: [ubuntu2404-mongo60, rhel8, arm64-debian12]
```

### Pre-release smoke checklist (manual, before tagging v2.0.0)

- [ ] All PR-blocking scenarios pass in CI
- [ ] Nightly scenarios pass (latest run)
- [ ] `ansible-lint` clean, `yamllint .` clean
- [ ] Manual deploy to staging shard cluster (`tests/hosts-shards`)
- [ ] Manual upgrade from v1.6.5 → v2.0.0 on a disposable VM — assert validate.yml catches every removed v1 var
- [ ] Manual arm64 deploy on Apple Silicon or AWS Graviton (1 standalone node)
- [ ] `docs/MIGRATION-v2.md` migration table covers every renamed and removed var
- [ ] B-spike report (if Approach B chosen) checked in
- [ ] CHANGELOG.md v2.0.0 entry written

## 10. Migration impact on users

Users upgrading from v1.x must:

1. Change role source: `superset1.mongodb` → `maprangzth.mongodb`
2. Bump version pin: `v1.6.5` → `v2.0.0`
3. Read `docs/MIGRATION-v2.md` and apply var renames / removals
4. If on MongoDB ≤ 5.0: upgrade the database to ≥ 6.0 **manually** before applying the role (out of role scope)
5. If on Amazon Linux: switch to RHEL / Rocky / AlmaLinux or stay on v1.x
6. If using `mongodb_net_ssl_*` vars: migrate to `mongodb_net_tls_*` per MongoDB 4.2+ syntax
7. If using MMS agent: deploy MMS separately (out of role scope) or move to MongoDB Atlas
8. If using `mongodb_cloud_*` free monitoring: feature deprecated upstream; no v2.0 replacement

## 11. Repo + branch strategy

```
maprangzth/ansible-role-mongodb
├── main           ← default branch (was `master`, renamed via GitHub UI)
│   └── tags: v2.0.0-rc1 → v2.0.0 → v2.0.x patches
├── v1.x           ← cut from commit 6276c10 (v1.6.5), security backports only
└── spike/community-mongodb-eval  ← short-lived B-spike branch
```

**Implementation order:**

1. Cut `v1.x` branch from current HEAD (`6276c10`) on `main` (current `master`)
2. Rename `master` → `main` via GitHub Settings → Branches
3. Open `spike/community-mongodb-eval` for the 3-day spike
4. Spike result → either commit B (continue on spike branch) or close spike, open `refactor/v2.0-foundation` branch
5. Implementation PRs land on `refactor/v2.0-foundation`
6. CI green → merge to `main`
7. Tag `v2.0.0-rc1`, dogfood for 1 week
8. Tag `v2.0.0`, write GitHub Release, publish to Galaxy as `maprangzth.mongodb`

**Branch protection:**
- `main`: require PR, require CI pass, allow self-merge (solo maintainer)
- `v1.x`: protected, security backports only

**License + attribution:**
- Keep MIT license
- `meta/main.yml`: `namespace: maprangzth`, `author: maprangzth (forked from Vitaly Kargin / superset1)`
- README header note: "Fork of `superset1/ansible-role-mongodb` (unmaintained since 2023). Diverged at v1.6.5."

## 12. Out of scope (explicitly deferred)

- Sub-project 2: Sharding modernization (config-shard support new in 7.0, idempotency improvements). Separate spec after v2.0.0 ships.
- Sub-project 3: Backup feature (`mongodump`, filesystem snapshot, oplog tailing for PITR, retention). Separate spec.
- Performance / benchmarking
- Helm chart / k8s operator integration
- Multi-region replicaset orchestration
- Encryption at rest config flow

## 13. Open issues to resolve during implementation

| Issue | Resolution path |
|---|---|
| `library/mongodb_status_edited.py` pymongo 4.x compatibility | Run script under pymongo 4.6 in a venv; fix deprecated API calls. May need rewrite if `MongoClient` URI parsing changed. |
| RHEL 8 default Python may not be 3.9 | Document `ansible_python_interpreter: /usr/libexec/platform-python` or `python3.9` install. Add prepare step in molecule rhel8 scenario. |
| AVX CPU requirement (MongoDB 5.0+) | Add note in README. Validation can `cat /proc/cpuinfo | grep -q avx` and warn. |
| Whether to publish to Ansible Galaxy or only via git URL | Defer — publish git URL first, Galaxy after v2.0.0 stable for 2 weeks. |
| Whether to ship a Vagrantfile refresh | Out of scope — current `tests/Vagrantfile` may be stale; flag in CHANGELOG for community contribution. |

## 14. Reference material consulted

- endoflife.date for MongoDB, RHEL, Ubuntu, Debian (queried 2026-05-22)
- Context7 `/mongodb/docs` for install repo paths, sharding setup, backup methods
- Context7 `/ansible-collections/community.mongodb` for role/module surface
- Council fan-out (OpenAI GPT-5.5 + Google Gemini 3.1 Pro) for approach decision

---
