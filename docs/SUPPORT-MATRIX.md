# MongoDB × OS × Architecture Support Matrix

**Generated:** 2026-05-23
**Source:** repo.mongodb.org (probed via `scripts/probe-mongodb-repos.sh`)
**Probe output:** see `/tmp/probe-output.tsv` for raw HTTP codes

## Supported combinations (HTTP 200)

### Debian / Ubuntu (apt repos — arch encoded in Packages files, not URL path)

| MongoDB | OS/codename | amd64 + arm64 |
|---|---|---|
| 6.0 | debian/bullseye | ✅ |
| 6.0 | debian/bookworm | ✅ |
| 6.0 | debian/trixie | ❌ |
| 6.0 | ubuntu/jammy | ✅ |
| 6.0 | ubuntu/noble | ❌ |
| 7.0 | debian/bullseye | ✅ |
| 7.0 | debian/bookworm | ✅ |
| 7.0 | debian/trixie | ✅ |
| 7.0 | ubuntu/jammy | ✅ |
| 7.0 | ubuntu/noble | ❌ |
| 8.0 | debian/bullseye | ❌ |
| 8.0 | debian/bookworm | ✅ |
| 8.0 | debian/trixie | ✅ |
| 8.0 | ubuntu/jammy | ✅ |
| 8.0 | ubuntu/noble | ✅ |

### RHEL / Rocky / AlmaLinux (yum repos — arch is in the URL path)

| MongoDB | OS/version | x86_64 | aarch64 |
|---|---|---|---|
| 6.0 | redhat/8 | ✅ | ✅ |
| 6.0 | redhat/9 | ✅ | ✅ |
| 6.0 | redhat/10 | ❌ | ❌ |
| 7.0 | redhat/8 | ✅ | ✅ |
| 7.0 | redhat/9 | ✅ | ✅ |
| 7.0 | redhat/10 | ✅ | ✅ |
| 8.0 | redhat/8 | ✅ | ✅ |
| 8.0 | redhat/9 | ✅ | ✅ |
| 8.0 | redhat/10 | ✅ | ✅ |

## Notes

- Debian/Ubuntu apt repos: arch is encoded in Packages files, not the URL path — both amd64 + arm64 share the same dist Release file. If Release returns 200, both architectures are typically available; verify with `Packages.gz` if specific arch needed.
- RHEL yum repos: arch is in the URL path. x86_64 and aarch64 probed independently.
- **MongoDB 7.0 + Ubuntu Noble (24.04)**: repo returned 404 — upstream has not published packages yet as of probe date.
- **MongoDB 6.0 + Ubuntu Noble (24.04)**: repo returned 404 — not supported.
- **MongoDB 8.0 + Debian Bullseye (11)**: repo returned 404 — MongoDB 8.0 dropped Debian 11 support.
- **MongoDB 6.0 + RHEL 10**: repo returned 404 — not yet published.
- **MongoDB 7.0 + RHEL 10**: repo returned 200 — available despite RHEL 10 being newer.

## Combinations excluded from v2.0 (per design spec §2)

- Amazon Linux — explicitly dropped
- MongoDB versions ≤ 5.0 — out of scope
- Debian 11 (bullseye) — EOL Aug 2026, out of v2.0 scope
- Debian 13 (trixie) — future addition once MongoDB publishes repos
- Ubuntu 26.04 — future addition
- RHEL 10 — future addition

## Probe reproducibility

To re-verify:
```bash
./scripts/probe-mongodb-repos.sh
```

Re-verify before each release to catch upstream repo changes.
