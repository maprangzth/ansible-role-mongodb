# maprangzth.mongodb

**v2.0.0** — Ansible role for MongoDB 7.0 / 8.0 (plus 6.0 deprecated tier)

Forked from [`superset1/ansible-role-mongodb`](https://github.com/superset1/ansible-role-mongodb) (unmaintained since 2023) at v1.6.5. MIT licensed.

> **Upgrading from v1.x?** Read [`docs/MIGRATION-v2.md`](docs/MIGRATION-v2.md) first. v2.0 is a clean-break release — several vars were renamed or removed.

---

## Platforms

### PR-blocking CI (all PRs must pass)

| Distribution | MongoDB 7.0 | MongoDB 8.0 | amd64 | arm64 |
|---|---|---|---|---|
| Debian 12 (Bookworm) | yes | yes | yes | yes |
| Ubuntu 22.04 (Jammy) | yes | yes | yes | — |
| Ubuntu 24.04 (Noble) | yes | yes | yes | — |
| RHEL / Rocky 9 | yes | yes | yes | yes |

### Nightly only (not blocking for PRs)

| Distribution | MongoDB | Notes |
|---|---|---|
| RHEL / Rocky 8 | 7.0, 8.0 | Requires `ansible_python_interpreter: /usr/bin/python3.9` |
| Debian 12 arm64 | 7.0, 8.0 | Nightly arm64 extended suite |
| MongoDB 6.0 (any) | all platforms | Deprecated tier; requires `mongodb_allow_eol_version: true` |

**Dropped in v2.0:** Amazon Linux (all versions), MongoDB ≤ 5.0, Ubuntu 16.04/18.04/20.04, Debian 8/9/10.

---

## Install

### Ansible Galaxy

```bash
ansible-galaxy role install maprangzth.mongodb,v2.0.0
```

### requirements.yml (git URL)

```yaml
- src: https://github.com/maprangzth/ansible-role-mongodb.git
  version: "v2.0.0"
  name: maprangzth.mongodb
```

### Collection dependency

v2.0 requires `community.mongodb >= 1.7.0`:

```bash
ansible-galaxy collection install -r requirements.yml
```

---

## Quick Start

### Standalone

```ini
# hosts.ini
[mongo_standalone]
db1.example.com
```

```yaml
# group_vars/mongo_standalone.yml
mongodb_version: "8.0"
mongodb_root_admin_password: "change-me"
mongodb_user_admin_password: "change-me"
mongodb_root_backup_password: "change-me"
mongodb_exporter_password: "change-me"
```

```yaml
# playbook.yml
- hosts: mongo_standalone
  become: true
  roles:
    - role: maprangzth.mongodb
```

### Replicaset

```ini
# hosts.ini
[mongo_cluster]
db1.example.com mongodb_master=True
db2.example.com
db3.example.com
```

```yaml
# group_vars/mongo_cluster.yml
mongodb_version: "8.0"

mongodb_replication_replSetName: "rs01"
mongodb_replication_oplogSizeMB: 4096

# Generate with: openssl rand -base64 756
mongodb_security_keyfile_content: |
  <output of openssl rand -base64 756>

mongodb_root_admin_password: "change-me"
mongodb_user_admin_password: "change-me"
mongodb_root_backup_password: "change-me"
mongodb_exporter_password: "change-me"
```

```yaml
# playbook.yml — always use serial: 1 for rolling restarts
- hosts: mongo_cluster
  become: true
  serial: 1
  roles:
    - role: maprangzth.mongodb
```

> **serial: 1** is required for replicaset plays to prevent simultaneous restarts that would lose quorum.

### RHEL / Rocky 8 note

Rocky 8 ships Python 3.6 by default. Install Python 3.9 on targets and set the interpreter:

```bash
# On each Rocky 8 target
dnf install -y python39
```

```yaml
# group_vars/rocky8_hosts.yml
ansible_python_interpreter: /usr/bin/python3.9
```

---

## Content

- [Platforms](#platforms)
- [Install](#install)
- [Quick Start](#quick-start)
- [Variables Reference](#variables-reference)
  - [Core](#core)
  - [User / group](#user--group)
  - [Network](#network)
  - [TLS](#tls)
  - [Process / systemd](#process--systemd)
  - [Security](#security)
  - [Storage](#storage)
  - [Logging](#logging)
  - [Operation Profiling](#operation-profiling)
  - [Replication](#replication)
  - [Sharding](#sharding)
  - [Inventory groups](#inventory-groups)
  - [Mongos](#mongos)
  - [Users / passwords](#users--passwords)
  - [mongodb-exporter](#mongodb-exporter)
  - [Uninstall mode](#uninstall-mode)
  - [Misc](#misc)
  - [Custom config escape hatch](#custom-config-escape-hatch)
- [Usage Examples](#usage-examples)
  - [Replicaset setup](#replicaset-setup)
  - [Sharded cluster](#sharded-cluster)
  - [TLS configuration](#tls-configuration)
  - [Custom roles and users](#custom-roles-and-users)
  - [Managing users at runtime](#managing-users-at-runtime)
  - [Password updates](#password-updates)
  - [Reset lost admin passwords](#reset-lost-admin-passwords)
  - [Prometheus exporter](#prometheus-exporter)
- [Tags](#tags)
- [License](#license)

---

## Variables Reference

All defaults are in `defaults/main.yml`. Variables are organized by section.

### Core

```yaml
mongodb_version: "8.0"              # MongoDB version to install. Supported: "6.0" (deprecated), "7.0", "8.0"
mongodb_major_version: "{{ mongodb_version[0:3] }}"  # Computed — do not override
mongodb_allow_major_upgrade: false  # Set true to opt in to in-place major version upgrade (manual step-wise upgrade required first)
mongodb_allow_eol_version: false    # Set true to allow MongoDB 6.0 (deprecated tier); role fails preflight if false and version is 6.0
mongodb_allow_non_serial_apply: false  # Set true to bypass rolling-restart preflight warning (not recommended)
```

### User / group

```yaml
mongodb_user: "{{ 'mongod' if ansible_os_family == 'RedHat' else 'mongodb' }}"
mongodb_group: "{{ mongodb_user }}"
```

### Network

```yaml
mongodb_net_bindIp: "0.0.0.0"      # Comma-separated IPs to bind; override for internal-only
mongodb_net_bind_ip_all: false      # Bind to all IPs (alternative to bindIp)
mongodb_net_ipv6: false             # Enable IPv6
mongodb_net_maxConns: 65536         # Max simultaneous connections
mongodb_net_port: 27017             # mongod listen port
```

### TLS

v2.0 uses flat `mongodb_net_tls_*` vars. See [`docs/MIGRATION-v2.md §4`](docs/MIGRATION-v2.md#4-tls-migration) for migration from v1 nested dicts.

```yaml
mongodb_net_tls_enabled: false
mongodb_net_tls_mode: ""                           # disabled|allowTLS|preferTLS|requireTLS
mongodb_net_tls_certificateKeyFile: ""             # Path to server PEM (cert + key) on target
mongodb_net_tls_CAFile: ""                         # Path to CA certificate on target
mongodb_net_tls_CRLFile: ""                        # Path to CRL file on target (optional)
mongodb_net_tls_clusterFile: ""                    # Path to inter-node cluster membership PEM
mongodb_net_tls_clusterCAFile: ""                  # Path to cluster CA PEM
mongodb_net_tls_allowConnectionsWithoutCertificates: false
mongodb_net_tls_allowInvalidCertificates: false    # Dev/test only
mongodb_net_tls_allowInvalidHostnames: false       # Dev/test only
mongodb_net_tls_FIPSMode: false
mongodb_net_tls_disabledProtocols: ""              # e.g., "TLS1_0,TLS1_1"
mongodb_net_tls_logVersions: ""                    # Log connections by TLS version
```

### Process / systemd

```yaml
mongodb_processManagement_fork: "{{ ansible_os_family == 'RedHat' }}"
mongodb_systemd_unit_limit_nofile: 64000
mongodb_systemd_unit_limit_nproc: 64000
mongodb_disable_transparent_hugepages: false       # Recommended true for production
mongodb_use_numa: false
```

### Security

```yaml
mongodb_security_authorization_enabled: true       # Enable access control
mongodb_security_javascript_enabled: false         # Disable server-side JS (recommended false)
mongodb_security_keyfile_path: /etc/mongodb-keyfile  # Path on target for keyfile
mongodb_security_keyfile_content: ""               # REQUIRED for replicasets. Generate: openssl rand -base64 756
```

### Storage

```yaml
mongodb_storage_dbPath: /var/lib/mongodb           # Data directory
mongodb_storage_engine: wiredTiger                 # Only wiredTiger supported in 6.0+
mongodb_storage_wiredTiger_cacheSizeGB: ""         # WiredTiger cache size in GB (empty = auto)
mongodb_storage_wiredTiger_directoryForIndexes: false  # Store indexes in separate directories
mongodb_storage_journal_enabled: true
mongodb_storage_dirperdb: false                    # One subdirectory per database
mongodb_storage_journal_commitIntervalMs: 100
```

### Logging

```yaml
mongodb_systemLog_destination: file               # file or syslog
mongodb_systemLog_logAppend: true                 # Append to log vs overwrite
mongodb_systemLog_path: /var/log/mongodb/mongod.log
```

### Operation Profiling

```yaml
mongodb_operationProfiling_slowOpThresholdMs: 100  # Log ops slower than this (ms)
mongodb_operationProfiling_mode: "off"             # off|slowOp|all
```

### Replication

```yaml
mongodb_replication_replSetName: ""               # Replicaset name. Required for replicaset/sharded topologies
mongodb_replication_oplogSizeMB: 4096             # Oplog size in MB
mongodb_replication_reconfigure: false            # Set true to reconfigure replicaset members (add/remove)
mongodb_replication_replindexprefetch: all        # Index prefetching for secondaries: none|_id_only|all
```

### Sharding

```yaml
mongodb_sharding_state: present                   # present|absent — whether to add shard to cluster
mongodb_sharding_clusterRole: ""                  # shardsvr|configsvr|"" (empty = not a sharding member)
mongodb_sharded_databases: []                     # List of databases to run sh.enableSharding() on
```

### Inventory groups

```yaml
mongodb_standalone_host_group: "mongo_standalone"
mongodb_replication_host_group: "mongo_cluster"
mongodb_sharded_host_group: "mongo_shard_"        # Prefix; shards are mongo_shard_01, mongo_shard_02, etc.
mongodb_config_host_group: "mongocfg_servers"
mongos_host_group: "mongos_servers"
```

### Mongos

```yaml
mongos_user: "{{ 'mongos' if ansible_os_family == 'RedHat' else 'mongodb' }}"
mongos_group: "{{ mongos_user }}"
mongos_net_port: 27017
mongos_net_bindIp: "0.0.0.0"
mongos_security_keyfile_path: "{{ mongodb_security_keyfile_path }}"
mongos_security_keyfile_content: "{{ mongodb_security_keyfile_content }}"
```

### Users / passwords

```yaml
mongodb_login_database: admin
mongodb_root_admin_name: mongoroot
mongodb_root_admin_password: ""                   # REQUIRED — set in vault or encrypted vars
mongodb_user_admin_name: mongoadm
mongodb_user_admin_password: ""                   # REQUIRED
mongodb_root_backup_name: mongobackup
mongodb_root_backup_password: ""                  # REQUIRED
mongodb_admin_update_password: false              # Set true to rotate admin passwords on every play
mongodb_users_update_password: false              # Set true to rotate normal user passwords on every play

mongodb_users: []
# - name: myapp
#   password: "secret"
#   roles: readWrite
#   database: myappdb
#   state: present          # present|absent (default: present)
#   update_password: false  # override global flag per user

mongodb_oplog_users: []
# - name: oplog_reader
#   password: "secret"

mongodb_custom_roles: []
# - name: read-and-create-index
#   state: present
#   database: myappdb
#   roles:
#     - role: read
#       db: myappdb
#   privileges:
#     - resource: {db: myappdb, collection: ""}
#       actions: [createIndex]
```

### mongodb-exporter

mongodb-exporter is pinned to v0.51.0 with SHA-256 checksums for both amd64 and arm64. Prevents silent drift to untested releases.

```yaml
mongodb_exporter_enabled: true
mongodb_exporter_version: "0.51.0"               # Pinned; change with caution
mongodb_exporter_user: "mongodb-exporter"
mongodb_exporter_group: "{{ mongodb_group }}"
mongodb_exporter_name: mongodbexporter
mongodb_exporter_password: ""                     # REQUIRED if exporter_enabled: true
mongodb_exporter_path: "/usr/local/bin/mongodb-exporter"
mongodb_exporter_temp_dir: "/tmp/mongodb_exporter"
mongodb_exporter_sha256:
  amd64: "01dfae78c737fb48761a715d779cade464a84cce7a2a70357ac4af469bade198"
  arm64: "f2f023d2d632c3b9cdc873558f26a8940efc197c1b36bbf96da17416a60eead6"
```

### Uninstall mode

```yaml
mongodb_uninstall_mode: remove    # remove: uninstall packages, keep data
                                  # purge: uninstall packages AND delete mongodb_storage_dbPath
```

Use `mongodb-uninstall` tag to trigger uninstall.

### Misc

```yaml
mongodb_manage_service: true           # Whether the role starts/restarts the service
mongodb_force_install: false           # Force reinstall (use for downgrades)
mongos_force_install: false
mongodb_package: mongodb-org           # Package name to install
mongodb_package_state: present         # present|latest|absent
mongodb_pymongo_pip_version: "4.6.0"   # PyMongo version for pip install
mongodb_reconfigure: false             # Force reconfiguration even if not changed
```

### Custom config escape hatch

```yaml
mongodb_config: {}   # Extra mongod.conf options as a nested dict (passed through to config template)
```

Example:

```yaml
mongodb_config:
  setParameter:
    diagnosticDataCollectionEnabled: false
```

---

## Usage Examples

### Replicaset setup

```ini
# hosts.ini
[mongo_cluster]
db1.example.com mongodb_master=True   # optional; if unset, first host in group is elected primary
db2.example.com
db3.example.com
db4.example.com
db5.example.com mongodb_arbiter=True  # optional arbiter member
```

```yaml
# group_vars/mongo_cluster.yml
mongodb_version: "8.0"
mongodb_replication_replSetName: "rs01"
mongodb_security_keyfile_content: "{{ lookup('env', 'MONGODB_KEYFILE') }}"
mongodb_root_admin_password: "{{ lookup('env', 'MONGODB_ROOT_PW') }}"
mongodb_user_admin_password: "{{ lookup('env', 'MONGODB_ADM_PW') }}"
mongodb_root_backup_password: "{{ lookup('env', 'MONGODB_BKP_PW') }}"
mongodb_exporter_password: "{{ lookup('env', 'MONGODB_EXP_PW') }}"
```

```yaml
# playbook.yml
- hosts: mongo_cluster
  become: true
  serial: 1
  roles:
    - role: maprangzth.mongodb
```

To add or remove replicaset members: update `hosts.ini`, ensure member count is odd, then run with `-e mongodb_replication_reconfigure=true`.

### Sharded cluster

```ini
# hosts.ini
[mongocfg_servers]
cfgsrv1.example.com
cfgsrv2.example.com
cfgsrv3.example.com

[mongos_servers]
router1.example.com
router2.example.com

[mongo_shard_01]
shard1a.example.com
shard1b.example.com
shard1c.example.com

[mongo_shard_02]
shard2a.example.com
shard2b.example.com
shard2c.example.com

[mongo_sharded_cluster:children]
mongocfg_servers
mongos_servers
mongo_shard_01
mongo_shard_02
```

```yaml
# group_vars/mongo_sharded_cluster.yml
mongodb_version: "8.0"
mongodb_security_keyfile_content: "{{ lookup('env', 'MONGODB_KEYFILE') }}"
mongodb_root_admin_password: "{{ lookup('env', 'MONGODB_ROOT_PW') }}"
mongodb_user_admin_password: "{{ lookup('env', 'MONGODB_ADM_PW') }}"
mongodb_root_backup_password: "{{ lookup('env', 'MONGODB_BKP_PW') }}"
mongodb_exporter_password: "{{ lookup('env', 'MONGODB_EXP_PW') }}"

# Enable sharding for specific databases
mongodb_sharded_databases:
  - app_database
  - analytics_database
```

### TLS configuration

Cert files must be present on targets before the role runs (use a pre-task or a cert-management role).

```yaml
# group_vars/all.yml — replicaset with TLS
mongodb_net_tls_enabled: true
mongodb_net_tls_mode: "requireTLS"
mongodb_net_tls_certificateKeyFile: "/etc/ssl/mongo/server.pem"
mongodb_net_tls_CAFile: "/etc/ssl/mongo/ca.pem"
# Inter-node cluster auth via separate cluster cert (recommended)
mongodb_net_tls_clusterFile: "/etc/ssl/mongo/cluster.pem"
mongodb_net_tls_clusterCAFile: "/etc/ssl/mongo/ca.pem"
```

```yaml
# playbook.yml — deploy certs then apply role
- hosts: mongo_cluster
  become: true
  serial: 1
  pre_tasks:
    - name: Deploy TLS certificates
      ansible.builtin.copy:
        src: "certs/{{ inventory_hostname }}.pem"
        dest: "/etc/ssl/mongo/server.pem"
        owner: mongod
        mode: "0400"
  roles:
    - role: maprangzth.mongodb
```

### Custom roles and users

```yaml
mongodb_custom_roles:
  - name: read-and-create-index
    state: present
    database: myappdb
    roles:
      - role: read
        db: myappdb
    privileges:
      - resource:
          db: myappdb
          collection: ""
        actions:
          - createIndex

mongodb_users:
  - name: appuser
    password: "app-password"
    roles: readWrite
    database: myappdb
  - name: appuser_ro
    password: "ro-password"
    roles: read-and-create-index
    database: myappdb
```

Run with `--tags mongodb-add-users` to safely add users to an already-running production database.

### Managing users at runtime

**Add users** (safe on running production database):
```bash
ansible-playbook playbook.yml -i hosts --tags mongodb-add-users
```

**Delete a user** (set `state: absent`):
```yaml
mongodb_users:
  - name: old_user
    database: myappdb
    state: absent
```

**Delete an oplog user:**
```yaml
mongodb_oplog_users:
  - name: oplog_reader
    state: absent
```

### Password updates

Update all admin passwords on every play:
```yaml
mongodb_admin_update_password: true
```

Update a specific user's password only:
```yaml
mongodb_users:
  - name: appuser
    password: "new-password"
    roles: readWrite
    database: myappdb
    update_password: true
```

### Reset lost admin passwords

If admin credentials are lost, run this two-step procedure:

```bash
# Step 1: disable auth, update passwords
ansible-playbook playbook.yml -i hosts \
  -t "mongodb,mongodb-force-restart" \
  -e '{mongodb_reconfigure: true, mongodb_security_authorization_enabled: false, mongodb_admin_update_password: true, mongodb_users_update_password: true, mongodb_exporter_force_install: true}'

# Step 2: re-enable auth
ansible-playbook playbook.yml -i hosts \
  -t "mongodb,mongodb-force-restart" \
  -e '{mongodb_reconfigure: true}'
```

### Prometheus exporter

The role installs and configures [percona/mongodb_exporter](https://github.com/percona/mongodb_exporter) v0.51.0 by default when `mongodb_exporter_enabled: true`.

The exporter binary is verified against pinned SHA-256 checksums for both amd64 and arm64. To disable:

```yaml
mongodb_exporter_enabled: false
```

To uninstall the exporter only (without touching MongoDB):

```bash
ansible-playbook playbook.yml -i hosts --tags mongodb-uninstall-exporter
```

---

## Tags

| Tag | Description |
|-----|-------------|
| `mongodb` | All mongod tasks (main entry point) |
| `mongodb-install` | Install MongoDB packages only |
| `mongodb-configure` | Configure mongod (mongod.conf, systemd, logrotate) |
| `mongodb-logrotate` | Configure logrotate only |
| `mongodb-replicaset` | Initialize or reconfigure replicaset |
| `mongodb-create-admin-users` | Create initial admin users |
| `mongodb-create-oplog-users` | Create oplog users |
| `mongodb-add-users` | Add/update/delete normal users (safe on running production) |
| `mongodb-commands` | Run additional ad-hoc MongoDB commands |
| `mongodb-force-restart` | Restart MongoDB service (default is start-only) |
| `mongodb-exporter` | Install/configure mongodb-exporter |
| `mongodb-uninstall` | Uninstall MongoDB + exporter (keeps data; see `mongodb_uninstall_mode` for purge) |
| `mongodb-uninstall-exporter` | Uninstall mongodb-exporter only |
| `mongodb-dbdelete` | Delete MongoDB data directory (destructive) |
| `mongos` | All mongos tasks |
| `mongos-install` | Install mongos packages only |
| `mongos-configure` | Configure mongos |
| `mongos-logrotate` | Configure mongos logrotate |
| `mongos-sharding` | Configure shards and sharded databases |
| `mongos-force-restart` | Restart mongos service |
| `mongos-uninstall` | Uninstall mongos |

---

## License

MIT

---

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for release history.

## Migration from v1.x

See [`docs/MIGRATION-v2.md`](docs/MIGRATION-v2.md) for the complete v1 → v2 migration guide.

## Support Matrix

See [`docs/SUPPORT-MATRIX.md`](docs/SUPPORT-MATRIX.md) for the MongoDB × OS × architecture support matrix.
