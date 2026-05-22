# v1.6.5 → v2.0.0 Variable Audit

**Generated:** 2026-05-23
**Source commit (v1 baseline):** 6276c10 (Version v1.6.5)
**Total unique vars in v1.6.5:** 138 (extracted from `defaults/main.yml` + `vars/main.yml`)

---

## Removed in v2.0

Total removed: **28**

### SSL legacy block (drop entire family — reject at `validate.yml`)

All `mongodb_net_ssl_*` vars are rejected at preflight. v2.0 uses `mongodb_net_tls_*` flat vars exclusively (§6.6 of spec).

- `mongodb_net_ssl_enabled` — legacy toggle; replaced by `mongodb_net_tls_enabled`
- `mongodb_net_ssl_config` — nested dict (dict variant); replaced by flat `mongodb_net_tls_*` vars
- `mongodb_net_ssl_PEMKeyFile_path` — path alias from `vars/main.yml`; replaced by `mongodb_net_tls_certificateKeyFile`
- `mongodb_net_ssl_CAFile_path` — path alias from `vars/main.yml`; replaced by `mongodb_net_tls_CAFile`
- `mongodb_net_ssl_CRLFile_path` — path alias from `vars/main.yml`; replaced by `mongodb_net_tls_CRLFile`
- `mongodb_net_ssl_clusterFile_path` — path alias from `vars/main.yml`; replaced by `mongodb_net_tls_clusterFile`
- `mongodb_net_ssl_clusterCAFile_path` — path alias from `vars/main.yml`; replaced by `mongodb_net_tls_clusterCAFile`

### TLS v1 schema (nested dict + path-suffix aliases — drop in favor of flat vars)

The v1 TLS implementation used a nested `mongodb_net_tls_config` dict and separate `*_path` vars in `vars/main.yml`. v2.0 replaces both with a flat `mongodb_net_tls_*` schema in `defaults/main.yml` (no `_path` suffix, operator sets path directly).

- `mongodb_net_tls_config` — nested dict in `defaults/main.yml`; replaced by flat `mongodb_net_tls_*` vars
- `mongodb_net_tls_certificateKeyFile_path` — path var in `vars/main.yml`; replaced by `mongodb_net_tls_certificateKeyFile`
- `mongodb_net_tls_CAFile_path` — path var in `vars/main.yml`; replaced by `mongodb_net_tls_CAFile`
- `mongodb_net_tls_CRLFile_path` — path var in `vars/main.yml`; replaced by `mongodb_net_tls_CRLFile`
- `mongodb_net_tls_clusterFile_path` — path var in `vars/main.yml`; replaced by `mongodb_net_tls_clusterFile`
- `mongodb_net_tls_clusterCAFile_path` — path var in `vars/main.yml`; replaced by `mongodb_net_tls_clusterCAFile`

### MMS agent (drop — MongoDB Ops Manager replaced MMS; agent no longer distributed)

- `mongodb_mms_agent_pkg`
- `mongodb_mms_group_id`
- `mongodb_mms_api_key`
- `mongodb_mms_base_url`

### Free cloud monitoring (deprecated upstream in MongoDB 6.0)

See: https://www.mongodb.com/docs/v6.0/administration/free-monitoring/#free-monitoring

- `mongodb_cloud_enabled`
- `mongodb_cloud_monitoring_free_state`

### mmapv1 storage (engine removed in MongoDB 4.2; v2.0 supports 6.0+)

- `mongodb_storage_quota_enforced`
- `mongodb_storage_quota_maxfiles`
- `mongodb_storage_smallfiles`
- `mongodb_storage_prealloc`

### Architecture conflation

- `bin_arch` — conflated single var; split into three explicit vars: `mongodb_apt_arch`, `mongodb_rpm_arch`, `mongodb_exporter_arch` (see spec §6.5)

### Other obsolete vars

- `os` — hard-coded `"linux"` string used only in `mongodb_exporter_link` URL; replaced by literal `linux` in the v2 link template (spec §6.7). No operator should set this.
- `vault_token` — `{{ lookup('env','VAULT_TOKEN') }}` convenience alias defined in `vars/main.yml`; not used consistently, not documented in README; operators use `lookup('env',...)` directly or a vault integration layer. Removed to avoid confusion.
- `vault_url` — `{{ lookup('env','VAULT_ADDR') }}` convenience alias; same rationale as `vault_token`.
- `mongodb_net_http_enabled` — MongoDB HTTP diagnostic interface was removed in MongoDB 3.6. v2.0 targets MongoDB 6.0+; this var is dead code.

---

## Renamed in v2.0 (old → new)

None — clean break uses new names directly.

---

## Kept identically (no change in v2.0)

Total kept: **110**

### Core / install

- `mongodb_version`
- `mongodb_package`
- `mongodb_package_state`
- `mongodb_force_install`
- `mongodb_reconfigure`
- `mongodb_daemon_name`
- `mongodb_manage_service`
- `mongodb_disable_transparent_hugepages`
- `mongodb_use_numa`
- `mongodb_pymongo_from_pip`
- `mongodb_pymongo_pip_version`
- `mongodb_admin_update_password`
- `mongodb_users_update_password`
- `mongodb_login_database`

### OS / runtime identity

- `mongodb_user`
- `mongodb_group`
- `mongodb_major_version` (computed)
- `mongodb_apt_keyserver`
- `mongodb_valid_groups` (computed)

### Network

- `mongodb_net_bindip`
- `mongodb_net_bind_ip_all`
- `mongodb_net_ipv6`
- `mongodb_net_maxconns`
- `mongodb_net_port`
- `mongodb_net_tls_enabled` (flat toggle — kept; flat config vars are NEW in v2.0, not in this audit)

### Security

- `mongodb_security_authorization_enabled`
- `mongodb_security_javascript_enabled`
- `mongodb_security_keyfile_path`
- `mongodb_keyfile_content`

### Storage

- `mongodb_storage_dbpath`
- `mongodb_storage_dirperdb`
- `mongodb_storage_engine`
- `mongodb_storage_journal_enabled`
- `mongodb_storage_journal_commitIntervalMs`
- `mongodb_storage_wiredtiger_cache_size`
- `mongodb_storage_wiredtiger_directory_for_indexes`

### Logging

- `mongodb_systemlog_destination`
- `mongodb_systemlog_logappend`
- `mongodb_systemlog_logrotate`
- `mongodb_systemlog_logrotate_config`
- `mongodb_systemlog_path`

### Systemd limits

- `mongodb_systemd_unit_limit_nofile`
- `mongodb_systemd_unit_limit_nproc`

### Operation profiling

- `mongodb_operation_profiling_slow_op_threshold_ms`
- `mongodb_operation_profiling_mode`

### Process management

- `mongodb_processmanagement_fork`

### Replication

- `mongodb_replication_enabled`
- `mongodb_replication_host_group`
- `mongodb_replication_replset`
- `mongodb_replication_replindexprefetch`
- `mongodb_replication_oplogsize`
- `mongodb_replication_oplogresize`
- `mongodb_replication_reconfigure`

### Sharding

- `mongodb_sharding_enabled` (computed)
- `mongodb_sharding_role` (computed)
- `mongodb_sharding_state`
- `mongodb_sharded_host_group`
- `mongodb_sharded_databases`
- `mongodb_standalone_host_group`

### Config server

- `mongodb_config_host_group`
- `mongodb_config_replication_replset_name`

### User management

- `mongodb_user_admin_name`
- `mongodb_user_admin_password`
- `mongodb_root_admin_name`
- `mongodb_root_admin_password`
- `mongodb_root_backup_name`
- `mongodb_root_backup_password`
- `mongodb_users`
- `mongodb_oplog_users`
- `mongodb_custom_roles`
- `mongodb_custom_backup_role` (computed)

### Exporter

- `mongodb_exporter_enabled`
- `mongodb_exporter_force_install`
- `mongodb_exporter_version`
- `mongodb_exporter_version_arbiter`
- `mongodb_exporter_link`
- `mongodb_exporter_path`
- `mongodb_exporter_checksum_link`
- `mongodb_exporter_checksum_path`
- `mongodb_exporter_temp_dir`
- `mongodb_exporter_user`
- `mongodb_exporter_group`
- `mongodb_exporter_name`
- `mongodb_exporter_password`

### Custom config passthrough

- `mongodb_config`

### Mongos

- `mongos_host_group`
- `mongos_daemon_name`
- `mongos_force_install`
- `mongos_package`
- `mongos_package_state`
- `mongos_reconfigure`
- `mongos_version`
- `mongos_user`
- `mongos_group`
- `mongos_net_port`
- `mongos_net_bindip`
- `mongos_net_bind_ip_all`
- `mongos_net_tls_enabled`
- `mongos_net_compressors`
- `mongos_certificate_key_file`
- `mongos_certificate_ca_file`
- `mongos_security_keyfile_path`
- `mongos_keyfile_content`
- `mongos_systemlog_destination`
- `mongos_systemlog_logappend`
- `mongos_systemlog_logrotate`
- `mongos_systemlog_logrotate_config`
- `mongos_systemlog_path`
- `mongos_systemd_unit_limit_nofile`
- `mongos_systemd_unit_limit_nproc`

---

## Vars found in README/tests but NOT in v1 defaults/vars

These are runtime/inventory vars that operators may set. They are set via `set_fact` or inventory host vars (not `defaults/main.yml`), so they do not appear in the extracted var list.

| Var | Type | Notes |
|-----|------|-------|
| `mongodb_main_group` | `set_fact` (task-computed) | Derived from `group_names` intersection with `mongodb_valid_groups`. Not an operator-settable default; computed at runtime. Kept in v2.0. |
| `mongodb_master` | Inventory host var | Optional boolean on a host entry (`mongodb_master=True`). If unset, first host in group is elected master. Not in defaults by design — host-level. Kept in v2.0. |
| `mongodb_arbiter` | Inventory host var | Optional boolean on a host entry (`mongodb_arbiter=True`). Marks a host as a replicaset arbiter. Host-level only. Kept in v2.0. |

> Note: The README-extracted list also contained partial token matches (`mongodb_exporter_` prefix fragments, `mongodb_net_ipv` without the `6` digit) from grep artifact in the original extraction regex. These are not real variable names; they are regex artifacts and excluded here.

---

## Completeness check

| Category | Count |
|----------|-------|
| Total in v1 defaults+vars | 138 |
| Removed | 28 |
| Renamed | 0 |
| Kept | 110 |
| **Sum (removed + renamed + kept)** | **138** |
| Reconciled | **yes** |

---

## Notes for `validate.yml` (Plan Task 2.14)

Every var in the **Removed** bucket needs an explicit `ansible.builtin.fail` task in `tasks/validate.yml`. The list of vars to enforce (27 operator-facing; excludes `os`, `vault_token`, `vault_url` which are internal-only and cannot be set by operators via inventory):

```yaml
# tasks/validate.yml — clean-break enforcement list
removed_v1_vars:
  # SSL legacy block
  - mongodb_net_ssl_enabled
  - mongodb_net_ssl_config
  - mongodb_net_ssl_PEMKeyFile_path
  - mongodb_net_ssl_CAFile_path
  - mongodb_net_ssl_CRLFile_path
  - mongodb_net_ssl_clusterFile_path
  - mongodb_net_ssl_clusterCAFile_path
  # TLS v1 nested schema
  - mongodb_net_tls_config
  - mongodb_net_tls_certificateKeyFile_path
  - mongodb_net_tls_CAFile_path
  - mongodb_net_tls_CRLFile_path
  - mongodb_net_tls_clusterFile_path
  - mongodb_net_tls_clusterCAFile_path
  # MMS agent
  - mongodb_mms_agent_pkg
  - mongodb_mms_group_id
  - mongodb_mms_api_key
  - mongodb_mms_base_url
  # Free cloud monitoring
  - mongodb_cloud_enabled
  - mongodb_cloud_monitoring_free_state
  # mmapv1 storage
  - mongodb_storage_quota_enforced
  - mongodb_storage_quota_maxfiles
  - mongodb_storage_smallfiles
  - mongodb_storage_prealloc
  # Architecture conflation
  - bin_arch
  # Dead code vars (MongoDB 3.6+ removed HTTP interface; unlikely to be set but guard anyway)
  - mongodb_net_http_enabled
```

> `os`, `vault_token`, and `vault_url` were internal `vars/main.yml` values (not operator-settable defaults). Operators cannot accidentally set them from inventory. Omit from enforcement list to avoid false positives.
>
> The `mongodb_net_ssl_config` nested dict also requires a separate `when: mongodb_net_ssl_config is defined and (mongodb_net_ssl_config | length > 0)` guard per spec §6.3 to catch the dict-variant usage.
