# community.mongodb pre-spike verification — 2026-05-23

**Collection version tested:** community.mongodb-1.7.12
**Ansible-core version:** 2.15.13
**pymongo version:** 4.6.x

---

## Roles present (verbatim `ls roles/`)

```
mongodb_auth/
mongodb_config/
mongodb_install/
mongodb_linux/
mongodb_mongod/
mongodb_mongos/
mongodb_repository/
mongodb_selinux/
```

**All 5 roles our design assumes are present:** `mongodb_repository`, `mongodb_mongod`, `mongodb_mongos`, `mongodb_config`, `mongodb_auth`. Three bonus roles also exist: `mongodb_install`, `mongodb_linux`, `mongodb_selinux`.

---

## Modules present (verbatim `ls plugins/modules/`)

```
mongodb_atlas_cluster.py
mongodb_atlas_ldap_user.py
mongodb_atlas_user.py
mongodb_atlas_whitelist.py
mongodb_balancer.py
mongodb_index.py
mongodb_info.py
mongodb_maintenance.py
mongodb_oplog.py
mongodb_parameter.py
mongodb_replicaset.py
mongodb_role.py
mongodb_schema.py
mongodb_shard.py
mongodb_shard_tag.py
mongodb_shard_zone.py
mongodb_shell.py
mongodb_shutdown.py
mongodb_status.py
mongodb_stepdown.py
mongodb_user.py
```

**All 5 modules our design assumes are present:** `mongodb_replicaset`, `mongodb_status`, `mongodb_user`, `mongodb_shard`, `mongodb_shell`. No `mongodb_info` note: that's a bonus module for diagnostic use.

---

## Variable surface per role

### mongodb_repository

**Full `defaults/main.yml`:**
```yaml
mongodb_version: "8.2"
mongodb_key_version: "{{ ((mongodb_version | string).split('.')[0] ~ '.0') if ((mongodb_version | string).split('.')[0] | int >= 8) else (mongodb_version | string) }}"
debian_packages:
  - apt-transport-https
  - curl
  - gnupg
apt_key: "/usr/share/keyrings/mongodb-server-{{ mongodb_key_version }}.gpg"
debian:
  apt_repository_repo: >
    deb {{ '[arch=amd64,arm64 signed-by=' ~ apt_key ~ ']' if ansible_facts['distribution'] == 'Ubuntu' else '[signed-by=' ~ apt_key ~ ']' }}
    https://repo.mongodb.org/apt/{{ ansible_facts['distribution']|lower }}
    {{ ansible_facts['distribution_release'] }}/mongodb-org/{{ mongodb_version }}
    {{ 'multiverse' if ansible_facts['distribution'] == 'Ubuntu' else 'main' }}
redhat:
  rpm_key_key: "https://www.mongodb.org/static/pgp/server-{{ mongodb_key_version }}.asc"
  yum_baseurl: "https://repo.mongodb.org/yum/{{ 'amazon' if ansible_facts['distribution'] == 'Amazon' else 'redhat' }}/{{ ansible_facts['distribution_major_version'] }}/mongodb-org/{{ mongodb_version }}/{{ ansible_facts['architecture'] }}/"
  yum_gpgkey: "https://www.mongodb.org/static/pgp/server-{{ mongodb_key_version }}.asc"
  yum_gpgcheck: true
  yum_description: "Official MongoDB {{ mongodb_version }} yum repo"
```

**Required-by-us variable check:**

| Variable | Present | Actual name in role | Notes |
|---|---|---|---|
| `mongodb_version` | YES | `mongodb_version` | Default `"8.2"` — also accepts 6.x, 7.x per key_version logic |
| `mongodb_net_bindIp` | NO | N/A | Not applicable — repository role only sets up the package repo |
| `mongodb_replication_replSetName` | NO | N/A | Not applicable |
| `mongodb_storage_dbPath` | NO | N/A | Not applicable |
| `mongodb_security_keyFile` | NO | N/A | Not applicable |
| `mongodb_net_tls_*` | NO | N/A | Not applicable |
| `mongodb_sharding_clusterRole` | NO | N/A | Not applicable |

**Gaps:** None that matter — `mongodb_version` is the only variable our spec uses from this role. All other expected vars belong to runtime roles, not the repository role.

---

### mongodb_mongod

**Full `defaults/main.yml`:**
```yaml
mongod_port: 27017
bind_ip: 0.0.0.0
bind_ip_all: false
log_path: "/var/log/mongodb/mongod.log"
repl_set_name: rs0
authorization: "enabled"
openssl_keyfile_path: /etc/keyfile
openssl_keyfile_content: |
  <256-char base64 default keyfile content>
mongodb_admin_user: admin
mongodb_admin_pwd: admin
mongod_package: "mongodb-org-server"
replicaset: true
sharding: false
net_compressors: null
mongod_config_template: "mongod.conf.j2"
skip_restart: true
db_path: "{{ '/var/lib/mongodb' if ansible_os_family == 'Debian' else '/var/lib/mongo' ... }}"
mongodb_use_tls: false
mongodb_disabled_tls_protocols: ""
mongodb_allow_connections_without_certificates: false
mongodb_logrotate_enabled: false
mongodb_logrotate_template: "mongodb.logrotate.j2"
mongodb_systemd_service_override: ""
```

**Required-by-us variable check:**

| Variable (spec name) | Present | Actual name in role | Notes |
|---|---|---|---|
| `mongodb_version` | NO (not in defaults) | Not in defaults — inherited from `mongodb_repository` via play vars | Template uses `mongodb_version` for journal conditional; must be set at play level |
| `mongodb_net_bindIp` | **NAME MISMATCH** | `bind_ip` | Our spec uses camelCase `mongodb_net_bindIp`; role uses `bind_ip` |
| `mongodb_replication_replSetName` | **NAME MISMATCH** | `repl_set_name` | Our spec uses dotted config path; role uses snake_case `repl_set_name` |
| `mongodb_storage_dbPath` | **NAME MISMATCH** | `db_path` | Our spec uses dotted config path; role uses `db_path` |
| `mongodb_security_keyFile` | **NAME MISMATCH** | `openssl_keyfile_path` | Role calls it `openssl_keyfile_path`; content in `openssl_keyfile_content` |
| `mongodb_net_tls_*` | **NAME MISMATCH** | `mongodb_use_tls`, `mongodb_certificate_key_file`, `mongodb_certificate_ca_file`, `mongodb_disabled_tls_protocols`, `mongodb_allow_connections_without_certificates` | Role uses flat `mongodb_use_tls` bool + separate vars — NOT a `mongodb_net_tls_*` namespace. `mongodb_certificate_key_file` and `mongodb_certificate_ca_file` are template vars not in defaults (must be provided when `mongodb_use_tls: true`) |
| `mongodb_sharding_clusterRole` | **NAME MISMATCH** | `sharding: true/false` only; clusterRole hardcoded to `shardsvr` in template | No variable to set `configsvr` — that is fixed in the `mongodb_config` role template |

**Gaps (actionable):**

1. **Variable naming convention mismatch**: Our spec assumes MongoDB config-path-style names (e.g., `mongodb_net_bindIp`, `mongodb_storage_dbPath`). The collection uses short snake_case names (`bind_ip`, `db_path`, `repl_set_name`). We must map or wrap these in our role's variable interface.
2. **TLS vars**: No `mongodb_net_tls_mode` variable — TLS is on/off only via `mongodb_use_tls`. Mode is hardcoded to `requireTLS`. Our spec must adapt.
3. **`sharding.clusterRole`**: In `mongodb_mongod`, this is hardcoded to `shardsvr` when `sharding: true`. There is no variable to set it to anything else from this role — `configsvr` is handled exclusively by `mongodb_config`.

---

### mongodb_mongos

**Full `defaults/main.yml`:**
```yaml
pid_file: /run/mongodb/mongos.pid
bind_ip: 0.0.0.0
bind_ip_all: false
log_path: "/var/log/mongodb/mongos.log"
mypy: python
mongos_package: "mongodb-org-mongos"
config_repl_set_name: cfg
config_servers: "config1:27019, config2:27019, config3:27019"
openssl_keyfile_path: /etc/keyfile
openssl_keyfile_content: |
  <256-char base64 default keyfile content>
net_compressors: null
mongos_config_template: "mongos.conf.j2"
skip_restart: true
mongodb_use_tls: false
mongodb_disabled_tls_protocols: ""
mongodb_allow_connections_without_certificates: false
```

**Required-by-us variable check:**

| Variable (spec name) | Present | Actual name in role | Notes |
|---|---|---|---|
| `mongodb_version` | NO | Not applicable | mongos does not pin version independently |
| `mongodb_net_bindIp` | **NAME MISMATCH** | `bind_ip` | Same pattern as mongod |
| `mongodb_replication_replSetName` | **NAME MISMATCH** | `config_repl_set_name` | This is the config RS name for mongos, not data RS |
| `mongodb_storage_dbPath` | NO | N/A | mongos has no storage |
| `mongodb_security_keyFile` | **NAME MISMATCH** | `openssl_keyfile_path` | Same as mongod |
| `mongodb_net_tls_*` | **NAME MISMATCH** | Same flat vars as mongod: `mongodb_use_tls`, `mongodb_certificate_key_file`, `mongodb_certificate_ca_file` | Same pattern |
| `mongodb_sharding_clusterRole` | N/A | N/A | mongos is the router; no clusterRole |

**Gaps:** Same naming convention mismatch as `mongodb_mongod`. Config server address string is `config_servers` (e.g., `"config1:27019, config2:27019, config3:27019"`) — our spec needs to account for this variable.

---

### mongodb_config

**Full `defaults/main.yml`:**
```yaml
pid_file: /var/run/mongodb/mongod.pid
bind_ip: 0.0.0.0
bind_ip_all: false
log_path: /var/log/mongodb/mongod.log
config_repl_set_name: cfg
authorization: enabled
openssl_keyfile_path: /etc/keyfile
openssl_keyfile_content: |
  <256-char base64 default keyfile content>
mongod_package: "mongodb-org-server"
replicaset: true
net_compressors: null
mongod_config_template: "configsrv.conf.j2"
skip_restart: true
db_path: "{{ '/var/lib/mongodb' if ansible_os_family == 'Debian' else '/var/lib/mongo' ... }}"
mongodb_use_tls: false
mongodb_disabled_tls_protocols: ""
mongodb_allow_connections_without_certificates: false
```

**Template confirms:** `clusterRole: configsvr` is hardcoded in `configsrv.conf.j2`. No variable governs it.

**Required-by-us variable check:**

| Variable (spec name) | Present | Actual name in role | Notes |
|---|---|---|---|
| `mongodb_version` | NO (not in defaults) | Inherited from play vars | Used in template journal conditional |
| `mongodb_net_bindIp` | **NAME MISMATCH** | `bind_ip` | Same pattern |
| `mongodb_replication_replSetName` | **NAME MISMATCH** | `config_repl_set_name` | Specific to config server RS |
| `mongodb_storage_dbPath` | **NAME MISMATCH** | `db_path` | Same pattern |
| `mongodb_security_keyFile` | **NAME MISMATCH** | `openssl_keyfile_path` | Same pattern |
| `mongodb_net_tls_*` | **NAME MISMATCH** | `mongodb_use_tls` + flat vars | Same TLS pattern |
| `mongodb_sharding_clusterRole` | **HARDCODED** | `configsvr` (hardcoded in template) | Cannot be changed via variable — always `configsvr` for this role |

**Gaps:** `clusterRole` is not configurable — it is hardcoded `configsvr` in the config server template. This is by design (the `mongodb_mongod` role hardcodes `shardsvr`). The two roles together provide both cluster roles without a variable needed.

---

### mongodb_auth (bonus — not in original step 3 list, but relevant)

**Full `defaults/main.yml`:**
```yaml
mongod_host: "localhost"
mongod_port: 27017
mongod_package: "mongodb-org-server"
authorization: "enabled"
mongodb_admin_user: admin
mongodb_admin_pwd: "{{ mongodb_default_admin_pwd }}"
mongodb_default_admin_pwd: admin
mongodb_admin_roles: "root"
mongodb_users: []
mongodb_force_update_password: no
mongodb_use_tls: false
mongodb_create_for_localhost_exception: /root/mongodb_admin.success
```

This role manages admin user bootstrapping and additional users via `mongodb_users` list. Compatible with our spec's auth bootstrap requirements.

---

## Naming Convention Summary

The collection uses **short snake_case** variable names, not MongoDB config-path-style names. Our spec's assumed names map as follows:

| Spec variable | Actual collection variable | Role(s) |
|---|---|---|
| `mongodb_version` | `mongodb_version` | `mongodb_repository` (also used in templates) |
| `mongodb_net_bindIp` | `bind_ip` + `bind_ip_all` | `mongodb_mongod`, `mongodb_mongos`, `mongodb_config` |
| `mongodb_replication_replSetName` | `repl_set_name` (mongod) / `config_repl_set_name` (config/mongos) | context-dependent |
| `mongodb_storage_dbPath` | `db_path` | `mongodb_mongod`, `mongodb_config` |
| `mongodb_security_keyFile` | `openssl_keyfile_path` (path) + `openssl_keyfile_content` (content) | `mongodb_mongod`, `mongodb_mongos`, `mongodb_config` |
| `mongodb_net_tls_mode` | `mongodb_use_tls` (bool, mode hardcoded `requireTLS`) | all runtime roles |
| `mongodb_net_tls_certificateKeyFile` | `mongodb_certificate_key_file` | all runtime roles |
| `mongodb_net_tls_CAFile` | `mongodb_certificate_ca_file` | all runtime roles |
| `mongodb_sharding_clusterRole: shardsvr` | `sharding: true` (hardcoded in mongod template) | `mongodb_mongod` |
| `mongodb_sharding_clusterRole: configsvr` | hardcoded in configsrv.conf.j2 | `mongodb_config` |

---

## Decision

**Spike proceed: YES**

All 5 roles and all 5 modules our design assumes are present in `community.mongodb:1.7.12`.

**Caveats to address before/during spike:**

1. **Variable name mapping required**: Our role's `defaults/main.yml` must expose our intended variable names (e.g., `mongodb_net_bindIp`) and translate them to collection role vars (e.g., `bind_ip`) when delegating. This is straightforward wrapper work.

2. **TLS mode not configurable**: The collection hardcodes TLS mode to `requireTLS`. If we need `allowTLS` or `preferTLS`, we must either use a custom template or accept this constraint. Recommend accepting `requireTLS`-only for v2.0.0.

3. **`clusterRole` not a variable**: `shardsvr` and `configsvr` are determined by which role (`mongodb_mongod` vs `mongodb_config`) is applied. Our interface layer should route node types to the correct role rather than trying to pass a `clusterRole` variable.

4. **`mongodb_version` not in runtime role defaults**: It must be set at the play/inventory level and flows through to templates. Our wrapper role must document this as a required variable.

5. **Gemini was wrong**: All assumed roles do exist. GPT + context7 were correct. The collection is feature-complete for our needs.

**Recommended approach**: Proceed with the spike. Build the v2.0 wrapper role's variable interface using our intended naming convention (MongoDB config-path style), and map to collection role variables in the delegation layer. The mapping table above is the authoritative translation.
