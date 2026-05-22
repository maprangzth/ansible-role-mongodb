# Changelog

All notable changes to `maprangzth.mongodb` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — v2.0.0

> **Breaking change release.** v2.0.0 is a clean-break refactor and is NOT backwards-compatible with v1.x.
> See `docs/MIGRATION-v2.md` for the full migration guide.
> Branch convention: `main` = v2.x active development, `master` = v1.x legacy backports (until v2.1.0).

### Added

- **MongoDB 7.0 and 8.0 support** — primary supported versions. All CI gates run against both.
- **MongoDB 6.0 deprecated tier** — supported with `mongodb_allow_eol_version: true` guard. Nightly CI only.
- **RHEL/Rocky 9 support** — first-class, PR-blocking CI on Rocky 9 (amd64 + arm64).
- **RHEL/Rocky 8 support** — nightly CI only; requires `ansible_python_interpreter: /usr/bin/python3.9`.
- **Ubuntu 24.04 (Noble)** support — PR-blocking CI.
- **Debian 12 (Bookworm)** support — PR-blocking CI (amd64 + arm64).
- **arm64 architecture support** — amd64 and arm64 tested in CI for Debian 12 and Rocky 9.
- **Flat TLS variable schema** (`mongodb_net_tls_*`) — replaces v1 nested `mongodb_net_ssl_config` / `mongodb_net_tls_config` dicts. Validated at preflight; role fails fast if v1 SSL/TLS vars are detected.
- **`mongodb_security_keyfile_content`** — new canonical var for the replicaset keyfile content (replaces `mongodb_keyfile_content`).
- **`mongodb_allow_major_upgrade`** — explicit opt-in guard for in-place major-version upgrades.
- **`mongodb_allow_eol_version`** — explicit opt-in required for MongoDB 6.0 (deprecated tier).
- **`mongodb_allow_non_serial_apply`** — bypass guard for rolling-restart preflight warning.
- **`mongodb_uninstall_mode`** — `remove` (default) vs. `purge` (deletes dbpath) uninstall control.
- **`mongodb_storage_wiredTiger_cacheSizeGB`** — replaces old `mongodb_storage_wiredtiger_cache_size`.
- **`mongodb_storage_wiredTiger_directoryForIndexes`** — replaces `mongodb_storage_wiredtiger_directory_for_indexes`.
- **`requirements.yml`** — pins `community.mongodb >= 1.7.0, < 2.0.0` for collection install.
- **`meta/main.yml`** — updated with namespace `maprangzth`, `min_ansible_version: "2.15"`, platforms Debian 12 / Ubuntu 22.04–24.04 / EL 8–9, `community.mongodb` collection dependency declared.
- **`docs/SUPPORT-MATRIX.md`** — checked-in MongoDB × OS × architecture support matrix with probe script.
- **`docs/V1-VARS-AUDIT.md`** — authoritative list of 28 removed vars, categorized (SSL/MMS/cloud/mmapv1/dead code).
- **mongodb-exporter pinned to v0.51.0** — SHA-256 checksums for both amd64 and arm64 baked into `defaults/main.yml`. Prevents silent drift to untested exporter releases.
- **`vars/main.yml`** — arch detection vars (`mongodb_apt_arch`, `mongodb_rpm_arch`, `mongodb_exporter_arch`) replacing single `bin_arch`. Support matrix dict for `validate.yml` assertions.

### Changed

- **Minimum Ansible version raised to 2.15** (was 2.9). ansible-core 2.15+ required.
- **Default MongoDB version changed to `8.0`** (was `4.4`).
- **Default `mongodb_storage_dbPath` changed to `/var/lib/mongodb`** (was `/data/db`). Matches OS package defaults on all supported platforms.
- **`mongodb_exporter_version` raised from 0.37.0 → 0.51.0** — aligns with MongoDB 7.0/8.0 metric changes.
- **`mongodb_pymongo_pip_version` raised from 4.2.0 → 4.6.0** — required for PyMongo async API compatibility.
- **`mongodb_user` / `mongodb_group`** — variable expressions simplified: `'mongod'` on RedHat, `'mongodb'` elsewhere (no change in semantics, expression cleaned up).
- **`mongodb_replication_oplogsize` renamed to `mongodb_replication_oplogSizeMB`** — aligns with mongod.conf camelCase schema.
- **`mongodb_operation_profiling_*` vars renamed** to `mongodb_operationProfiling_slowOpThresholdMs` / `mongodb_operationProfiling_mode` — aligns with mongod.conf.
- **`mongodb_systemlog_*` vars renamed** to `mongodb_systemLog_*` camelCase — aligns with mongod.conf.
- **`mongodb_storage_dbpath` renamed** to `mongodb_storage_dbPath` — aligns with mongod.conf.
- **`mongodb_processmanagement_fork` renamed** to `mongodb_processManagement_fork` — aligns with mongod.conf.
- **`mongodb_net_bindip` renamed** to `mongodb_net_bindIp` — aligns with mongod.conf.
- **`mongodb_net_maxconns` renamed** to `mongodb_net_maxConns` — aligns with mongod.conf.
- **`mongodb_replication_replset` renamed** to `mongodb_replication_replSetName` — aligns with mongod.conf.
- **`mongos_net_bindip` renamed** to `mongos_net_bindIp` — consistency.
- **per-OS vars files deleted** (`vars/Amazon.yml`, `vars/Debian.yml`, `vars/Ubuntu.yml`, `vars/RedHat.yml`) — `community.mongodb` collection owns repository setup; no per-OS overrides needed in this role.

### Removed

See `docs/MIGRATION-v2.md` → Removed Variables table for the complete list with v2 replacements.

- **`mongodb_net_ssl_enabled`** and entire `mongodb_net_ssl_config` nested dict — replaced by flat `mongodb_net_tls_*` vars.
- **`mongodb_net_tls_config`** nested dict — replaced by flat `mongodb_net_tls_*` vars.
- **`mongodb_net_ssl_*_path` / `mongodb_net_tls_*_path` aliases** in `vars/main.yml` — removed entirely.
- **`mongodb_mms_agent_pkg`**, **`mongodb_mms_group_id`**, **`mongodb_mms_api_key`**, **`mongodb_mms_base_url`** — MongoDB Ops Manager (formerly MMS) agent support removed; agent is no longer distributed publicly.
- **`mongodb_cloud_enabled`**, **`mongodb_cloud_monitoring_free_state`** — MongoDB free cloud monitoring deprecated upstream in 6.0.
- **`mongodb_storage_quota_enforced`**, **`mongodb_storage_quota_maxfiles`**, **`mongodb_storage_smallfiles`**, **`mongodb_storage_prealloc`** — mmapv1-only options; mmapv1 storage engine removed in MongoDB 4.2. v2.0 targets 6.0+.
- **`mongodb_net_http_enabled`** — HTTP diagnostic interface removed in MongoDB 3.6. Dead code.
- **`bin_arch`** — conflated single-arch var; replaced by `mongodb_apt_arch`, `mongodb_rpm_arch`, `mongodb_exporter_arch`.
- **`os`** (internal `vars/main.yml` string `"linux"`) — replaced by literal in `mongodb_exporter_link` template.
- **`vault_token`**, **`vault_url`** — internal `vars/main.yml` convenience aliases for `lookup('env',...)`. Removed to avoid confusion with operator-managed vault integration.
- **`mongodb_keyfile_content`** — replaced by `mongodb_security_keyfile_content` (no functional change, naming aligned with security block).
- **Amazon Linux support** — all versions dropped; MongoDB no longer ships Amazon Linux packages for the supported 7.0/8.0 versions.
- **MongoDB ≤ 5.0 support** — versions 3.4, 3.6, 4.0, 4.2, 4.4, 5.0 are not supported by v2.0. MongoDB 6.0 is supported in deprecated tier only.
- **MMS automation agent tasks** — `tasks/mms.yml` and associated logic removed.
- **`vars/Amazon.yml`**, **`vars/Debian.yml`**, **`vars/Ubuntu.yml`**, **`vars/RedHat.yml`** — per-OS var files deleted.

### Security

- Keyfile deploy now uses `mode: "0400"` and enforces `no_log: true` across all keyfile tasks.
- `validate.yml` preflight now explicitly fails if any v1 SSL (`mongodb_net_ssl_*`) or v1 MMS vars are detected in inventory, preventing silent misconfiguration.

---

## [v1.6.5] — 2024-03-xx

> Legacy v1.x line. Maintained on `master` branch with security backports only until v2.1.0.
> Forked from `superset1/ansible-role-mongodb` (unmaintained since 2023).

- Added example to README: "Reset lost admin and user passwords"
- Added `mongodb_cloud_enabled: false` (deprecated upstream)

## [v1.6.4]

- (see git log on `master` branch)

## [v1.6.3]

- (see git log on `master` branch)

---

[Unreleased]: https://github.com/maprangzth/ansible-role-mongodb/compare/v1.6.5...HEAD
[v1.6.5]: https://github.com/maprangzth/ansible-role-mongodb/releases/tag/v1.6.5
