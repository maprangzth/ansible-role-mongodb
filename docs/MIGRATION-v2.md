# Migration Guide — v1.x → v2.0.0

This guide covers everything needed to upgrade from any v1.x release of `maprangzth.mongodb` (forked from `superset1/ansible-role-mongodb`) to v2.0.0.

**v2.0.0 is a clean-break release.** Several variables were removed and renamed. The role will fail at preflight (`tasks/validate.yml`) if deprecated v1 vars are detected in your inventory — this is intentional.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Removed Variables](#2-removed-variables)
3. [Renamed Variables](#3-renamed-variables)
4. [TLS Migration](#4-tls-migration)
5. [New Required Variables](#5-new-required-variables)
6. [Branch and Install Changes](#6-branch-and-install-changes)
7. [Example: v1 → v2 group_vars diff](#7-example-v1--v2-group_vars-diff)
8. [CI and Molecule changes](#8-ci-and-molecule-changes)

---

## 1. Prerequisites

### 1.1 MongoDB version

v2.0.0 supports **MongoDB 6.0, 7.0, 8.0** only. MongoDB ≤ 5.0 is not supported.

If your cluster is on MongoDB ≤ 5.0 you must upgrade **step-wise** before applying v2.0.0:

```
4.4 → set FCV 4.4 → upgrade to 5.0
5.0 → set FCV 5.0 → upgrade to 6.0
6.0 → set FCV 6.0 → upgrade to 7.0
7.0 → set FCV 7.0 → upgrade to 8.0
```

Each upgrade step: upgrade binaries on secondaries (one at a time), then primary, then step-up to next FCV using `db.adminCommand({setFeatureCompatibilityVersion: "X.Y"})`.

Do NOT skip versions. MongoDB enforces FCV ordering.

MongoDB 6.0 is in the **deprecated tier** in v2.0. It requires `mongodb_allow_eol_version: true` to use. Plan to upgrade to 7.0 or 8.0 shortly after migrating to v2.0.

### 1.2 RHEL / Rocky 8

RHEL 8 and Rocky 8 ship Python 3.6 as system Python. Ansible module operations against MongoDB 7.0+ require Python 3.9+ and PyMongo 4.6+.

Before running v2.0:

```bash
# On each RHEL/Rocky 8 target
dnf install -y python39 python39-pip
```

In your inventory or `group_vars`:

```yaml
# group_vars for RHEL/Rocky 8 hosts
ansible_python_interpreter: /usr/bin/python3.9
```

### 1.3 Ansible and collection requirements

- **ansible-core 2.15+** is required (was 2.9+ in v1.x).
- **`community.mongodb` >= 1.7.0, < 2.0.0** is required.

Install the collection before running the role:

```bash
ansible-galaxy collection install -r requirements.yml
```

### 1.4 Pin to a tag, not a branch

v1.x Galaxy/git users typically pinned to `master`. In v2.0, `master` points to the v1.x legacy line. The v2.x active branch is `main`.

Always pin to a tag:

```yaml
# requirements.yml (roles)
- src: https://github.com/maprangzth/ansible-role-mongodb.git
  version: "v2.0.0"
  name: maprangzth.mongodb
```

Or via Ansible Galaxy:

```bash
ansible-galaxy role install maprangzth.mongodb,v2.0.0
```

---

## 2. Removed Variables

These variables are completely removed in v2.0. If any are detected in your inventory at play time, `tasks/validate.yml` will fail the play with an explicit error message and remediation hint.

### 2.1 SSL legacy block

The `mongodb_net_ssl_*` block was the pre-MongoDB-4.2 SSL API. v2.0 targets 6.0+; this block is gone entirely.

| v1 variable | Action | v2 replacement |
|-------------|--------|----------------|
| `mongodb_net_ssl_enabled` | Remove | Use `mongodb_net_tls_enabled: true` |
| `mongodb_net_ssl_config` | Remove (entire dict) | Use flat `mongodb_net_tls_*` vars (see §4) |
| `mongodb_net_ssl_PEMKeyFile_path` | Remove | Use `mongodb_net_tls_certificateKeyFile` |
| `mongodb_net_ssl_CAFile_path` | Remove | Use `mongodb_net_tls_CAFile` |
| `mongodb_net_ssl_CRLFile_path` | Remove | Use `mongodb_net_tls_CRLFile` |
| `mongodb_net_ssl_clusterFile_path` | Remove | Use `mongodb_net_tls_clusterFile` |
| `mongodb_net_ssl_clusterCAFile_path` | Remove | Use `mongodb_net_tls_clusterCAFile` |

### 2.2 TLS v1 nested schema

v1 also used a nested `mongodb_net_tls_config` dict alongside `*_path` aliases. Both are gone in v2.

| v1 variable | Action | v2 replacement |
|-------------|--------|----------------|
| `mongodb_net_tls_config` | Remove (entire dict) | Use flat `mongodb_net_tls_*` vars (see §4) |
| `mongodb_net_tls_certificateKeyFile_path` | Remove | Use `mongodb_net_tls_certificateKeyFile` |
| `mongodb_net_tls_CAFile_path` | Remove | Use `mongodb_net_tls_CAFile` |
| `mongodb_net_tls_CRLFile_path` | Remove | Use `mongodb_net_tls_CRLFile` |
| `mongodb_net_tls_clusterFile_path` | Remove | Use `mongodb_net_tls_clusterFile` |
| `mongodb_net_tls_clusterCAFile_path` | Remove | Use `mongodb_net_tls_clusterCAFile` |

### 2.3 MMS agent

MongoDB Ops Manager (formerly MMS) no longer distributes the monitoring agent publicly. These vars were no-ops in recent v1.x releases.

| v1 variable | Action |
|-------------|--------|
| `mongodb_mms_agent_pkg` | Remove — no replacement |
| `mongodb_mms_group_id` | Remove — no replacement |
| `mongodb_mms_api_key` | Remove — no replacement |
| `mongodb_mms_base_url` | Remove — no replacement |

### 2.4 Free cloud monitoring

MongoDB deprecated free cloud monitoring in 6.0 and removed it in 7.0.

| v1 variable | Action |
|-------------|--------|
| `mongodb_cloud_enabled` | Remove — no replacement |
| `mongodb_cloud_monitoring_free_state` | Remove — no replacement |

### 2.5 mmapv1 storage options

The mmapv1 storage engine was removed in MongoDB 4.2. v2.0 targets 6.0+; these vars are dead code.

| v1 variable | Action |
|-------------|--------|
| `mongodb_storage_quota_enforced` | Remove — no replacement |
| `mongodb_storage_quota_maxfiles` | Remove — no replacement |
| `mongodb_storage_smallfiles` | Remove — no replacement |
| `mongodb_storage_prealloc` | Remove — no replacement |

### 2.6 Architecture and internal vars

| v1 variable | Action | v2 replacement |
|-------------|--------|----------------|
| `bin_arch` | Remove | `mongodb_apt_arch`, `mongodb_rpm_arch`, `mongodb_exporter_arch` (auto-detected from `ansible_architecture`) |
| `mongodb_net_http_enabled` | Remove | No replacement (HTTP interface removed in MongoDB 3.6) |
| `os` | Remove (internal) | Literal `linux` in `mongodb_exporter_link` template; not operator-settable |
| `vault_token` | Remove (internal) | Use `lookup('env', 'VAULT_TOKEN')` directly in your vars |
| `vault_url` | Remove (internal) | Use `lookup('env', 'VAULT_ADDR')` directly in your vars |

### 2.7 Keyfile content rename

| v1 variable | Action | v2 replacement |
|-------------|--------|----------------|
| `mongodb_keyfile_content` | Rename | `mongodb_security_keyfile_content` |
| `mongos_keyfile_content` | Rename | `mongos_security_keyfile_content` |

---

## 3. Renamed Variables

These variables changed name to align with mongod.conf camelCase schema. The v1 names will cause a validate.yml failure if used.

| v1 name | v2 name | Notes |
|---------|---------|-------|
| `mongodb_net_bindip` | `mongodb_net_bindIp` | camelCase alignment |
| `mongodb_net_maxconns` | `mongodb_net_maxConns` | camelCase alignment |
| `mongodb_replication_replset` | `mongodb_replication_replSetName` | camelCase alignment |
| `mongodb_replication_oplogsize` | `mongodb_replication_oplogSizeMB` | camelCase alignment |
| `mongodb_storage_dbpath` | `mongodb_storage_dbPath` | camelCase alignment |
| `mongodb_storage_wiredtiger_cache_size` | `mongodb_storage_wiredTiger_cacheSizeGB` | camelCase alignment |
| `mongodb_storage_wiredtiger_directory_for_indexes` | `mongodb_storage_wiredTiger_directoryForIndexes` | camelCase alignment |
| `mongodb_systemlog_destination` | `mongodb_systemLog_destination` | camelCase alignment |
| `mongodb_systemlog_logappend` | `mongodb_systemLog_logAppend` | camelCase alignment |
| `mongodb_systemlog_path` | `mongodb_systemLog_path` | camelCase alignment |
| `mongodb_processmanagement_fork` | `mongodb_processManagement_fork` | camelCase alignment |
| `mongodb_operation_profiling_slow_op_threshold_ms` | `mongodb_operationProfiling_slowOpThresholdMs` | camelCase alignment |
| `mongodb_operation_profiling_mode` | `mongodb_operationProfiling_mode` | camelCase alignment |
| `mongos_net_bindip` | `mongos_net_bindIp` | camelCase alignment |

---

## 4. TLS Migration

### v1 approach (nested dict)

v1 used one of two nested dict patterns:

**v1 SSL pattern (MongoDB < 4.2 API):**
```yaml
mongodb_net_ssl_enabled: true
mongodb_net_ssl_config:
  mode: "requireSSL"
  PEMKeyFileContent: "{{ lookup(...) }}"
  CAFileContent: "{{ lookup(...) }}"
```

**v1 TLS pattern (MongoDB >= 4.2 API, nested dict):**
```yaml
mongodb_net_tls_enabled: true
mongodb_net_tls_config:
  mode: "requireTLS"
  certificateKeyFileContent: "{{ lookup(...) }}"
  CAFileContent: "{{ lookup(...) }}"
```

### v2 approach (flat vars)

v2 uses flat `mongodb_net_tls_*` vars. File **paths** are set directly (the role deploys the file from vault/vars; you provide the destination path on the target).

```yaml
mongodb_net_tls_enabled: true
mongodb_net_tls_mode: "requireTLS"
mongodb_net_tls_certificateKeyFile: "/etc/ssl/mongo/server.pem"
mongodb_net_tls_CAFile: "/etc/ssl/mongo/ca.pem"
# For inter-node cluster auth via TLS (optional, recommended for replicasets)
mongodb_net_tls_clusterFile: "/etc/ssl/mongo/cluster.pem"
mongodb_net_tls_clusterCAFile: "/etc/ssl/mongo/ca.pem"
```

The content of the PEM files is managed separately (e.g., via `ansible.builtin.copy` in a pre-task, or a separate cert-management role). The `maprangzth.mongodb` role only writes paths to `mongod.conf`.

### Full flat TLS variable reference

| Variable | Default | Description |
|----------|---------|-------------|
| `mongodb_net_tls_enabled` | `false` | Enable TLS listener |
| `mongodb_net_tls_mode` | `""` | `disabled\|allowTLS\|preferTLS\|requireTLS` |
| `mongodb_net_tls_certificateKeyFile` | `""` | Path to server PEM (cert + key) on target |
| `mongodb_net_tls_CAFile` | `""` | Path to CA PEM on target |
| `mongodb_net_tls_CRLFile` | `""` | Path to CRL PEM on target (optional) |
| `mongodb_net_tls_clusterFile` | `""` | Path to cluster membership PEM on target |
| `mongodb_net_tls_clusterCAFile` | `""` | Path to cluster CA PEM on target |
| `mongodb_net_tls_allowConnectionsWithoutCertificates` | `false` | Allow clients without certs |
| `mongodb_net_tls_allowInvalidCertificates` | `false` | Allow invalid/self-signed certs (dev only) |
| `mongodb_net_tls_allowInvalidHostnames` | `false` | Disable hostname validation (dev only) |
| `mongodb_net_tls_FIPSMode` | `false` | Enable FIPS mode |
| `mongodb_net_tls_disabledProtocols` | `""` | Comma-separated disabled TLS versions |
| `mongodb_net_tls_logVersions` | `""` | Log connections using specified TLS versions |

---

## 5. New Required Variables

These variables are **new in v2.0** and have no v1 equivalent. Some are required under specific conditions.

### 5.1 Required when replicaset enabled

When `mongodb_replication_replSetName` is non-empty (i.e., you are running a replicaset or sharded cluster), the following var is required:

```yaml
mongodb_security_keyfile_content: |
  <base64 string from: openssl rand -base64 756>
```

In v1, the equivalent was `mongodb_keyfile_content`. The content format is identical — only the variable name changed.

The role will validate this is non-empty when replication is enabled and fail at preflight if it is missing.

### 5.2 Required for MongoDB 6.0

```yaml
mongodb_allow_eol_version: true
```

MongoDB 6.0 has reached End of Life. The role blocks installation of 6.0 unless this guard is explicitly set.

### 5.3 Required admin passwords

These were also required in v1; documenting here for completeness:

```yaml
mongodb_root_admin_password: ""    # required, non-empty
mongodb_user_admin_password: ""    # required, non-empty
mongodb_root_backup_password: ""   # required, non-empty
mongodb_exporter_password: ""      # required if mongodb_exporter_enabled: true
```

### 5.4 RHEL 8 — python interpreter

```yaml
ansible_python_interpreter: /usr/bin/python3.9
```

Required on RHEL/Rocky 8 hosts. Set in your `host_vars` or `group_vars` for the RHEL 8 group.

---

## 6. Branch and Install Changes

### Branch convention

| Branch | Content |
|--------|---------|
| `main` | v2.x active development |
| `master` | v1.x legacy (security backports only, until v2.1.0) |
| `v1.x` | Frozen v1.6.5 baseline |

Existing installations that install from `master` will continue to receive v1.x until v2.1.0 (when `master` will be retired). If you want v2.0, **switch to the `main` branch or pin to `v2.0.0` tag**.

### Galaxy install

```bash
# Install v2.0.0 via Ansible Galaxy
ansible-galaxy role install maprangzth.mongodb,v2.0.0

# Install v1.x (legacy)
ansible-galaxy role install maprangzth.mongodb,v1.6.5
```

### requirements.yml (git URL)

```yaml
- src: https://github.com/maprangzth/ansible-role-mongodb.git
  version: "v2.0.0"
  name: maprangzth.mongodb
```

---

## 7. Example: v1 → v2 group_vars diff

### v1 group_vars/all.yml (replicaset with TLS)

```yaml
# v1 — group_vars/all.yml
mongodb_version: "6.0"

mongodb_net_tls_enabled: true
mongodb_net_tls_config:
  mode: "requireTLS"
  certificateKeyFileContent: "{{ lookup('hashi_vault', 'secret=mongo:certKeyContent token={{ vault_token }} url={{ vault_url }}') }}"
  CAFileContent: "{{ lookup('hashi_vault', 'secret=mongo:caContent token={{ vault_token }} url={{ vault_url }}') }}"

mongodb_keyfile_content: "{{ lookup('hashi_vault', 'secret=mongo:keyfile token={{ vault_token }} url={{ vault_url }}') }}"

mongodb_root_admin_password: "{{ lookup('hashi_vault', 'secret=mongo:root_pw token={{ vault_token }} url={{ vault_url }}') }}"
mongodb_user_admin_password: "{{ lookup('hashi_vault', 'secret=mongo:adm_pw token={{ vault_token }} url={{ vault_url }}') }}"
mongodb_root_backup_password: "{{ lookup('hashi_vault', 'secret=mongo:bkp_pw token={{ vault_token }} url={{ vault_url }}') }}"
mongodb_exporter_password: "{{ lookup('hashi_vault', 'secret=mongo:exp_pw token={{ vault_token }} url={{ vault_url }}') }}"

mongodb_replication_replset: "rs01"
mongodb_replication_oplogsize: 4096
```

### v2 group_vars/all.yml (equivalent, replicaset with TLS)

```yaml
# v2 — group_vars/all.yml
mongodb_version: "8.0"                         # upgraded from 6.0

# TLS: flat vars instead of nested dict
# (cert/key files are deployed separately via a pre-task or cert role)
mongodb_net_tls_enabled: true
mongodb_net_tls_mode: "requireTLS"
mongodb_net_tls_certificateKeyFile: "/etc/ssl/mongo/server.pem"
mongodb_net_tls_CAFile: "/etc/ssl/mongo/ca.pem"
mongodb_net_tls_clusterFile: "/etc/ssl/mongo/cluster.pem"

# Keyfile renamed
mongodb_security_keyfile_content: "{{ lookup('hashi_vault', 'secret=mongo:keyfile token=' ~ lookup('env','VAULT_TOKEN') ~ ' url=' ~ lookup('env','VAULT_ADDR')) }}"

# Passwords (vault_token / vault_url removed — use lookup('env',...) directly)
mongodb_root_admin_password: "{{ lookup('hashi_vault', 'secret=mongo:root_pw token=' ~ lookup('env','VAULT_TOKEN') ~ ' url=' ~ lookup('env','VAULT_ADDR')) }}"
mongodb_user_admin_password: "{{ lookup('hashi_vault', 'secret=mongo:adm_pw token=' ~ lookup('env','VAULT_TOKEN') ~ ' url=' ~ lookup('env','VAULT_ADDR')) }}"
mongodb_root_backup_password: "{{ lookup('hashi_vault', 'secret=mongo:bkp_pw token=' ~ lookup('env','VAULT_TOKEN') ~ ' url=' ~ lookup('env','VAULT_ADDR')) }}"
mongodb_exporter_password: "{{ lookup('hashi_vault', 'secret=mongo:exp_pw token=' ~ lookup('env','VAULT_TOKEN') ~ ' url=' ~ lookup('env','VAULT_ADDR')) }}"

# Replication — renamed vars (camelCase)
mongodb_replication_replSetName: "rs01"
mongodb_replication_oplogSizeMB: 4096
```

### Key diff summary

| Change | v1 | v2 |
|--------|----|----|
| TLS config | nested `mongodb_net_tls_config` dict | flat `mongodb_net_tls_*` vars |
| Keyfile | `mongodb_keyfile_content` | `mongodb_security_keyfile_content` |
| Vault shortcuts | `vault_token` / `vault_url` | `lookup('env','VAULT_TOKEN')` directly |
| Replicaset name | `mongodb_replication_replset` | `mongodb_replication_replSetName` |
| Oplog size | `mongodb_replication_oplogsize` | `mongodb_replication_oplogSizeMB` |
| Default MongoDB version | `4.4` | `8.0` |

---

## 8. CI and Molecule changes

If you maintain a fork or extend the role with your own Molecule scenarios:

- Molecule scenarios now target **Debian 12, Ubuntu 22.04, Ubuntu 24.04, Rocky 9** as PR-blocking platforms.
- **Rocky 8 and arm64** are nightly-only (not blocking for PRs).
- Molecule default driver: `docker` with `geerlingguy/docker-*-ansible` images or equivalent.
- `molecule/default/converge.yml` must include `serial: 1` for replicaset scenarios to test rolling behavior.
- Exporter tests should verify `mongodb_exporter_version: "0.51.0"` (the pinned v2 default).

---

For questions or issues with migration, open an issue at https://github.com/maprangzth/ansible-role-mongodb/issues.
