#!/usr/bin/env bash
# Probe MongoDB repos for (version × OS × arch) availability.
# Output: tab-separated rows: <mongodb>\t<os>\t<arch>\t<http_code>
set -u

declare -a MONGO_VERSIONS=(6.0 7.0 8.0)

probe() {
  local url="$1"
  curl -sI -o /dev/null -w "%{http_code}" --max-time 10 "$url"
}

# Debian + Ubuntu (apt)
for v in "${MONGO_VERSIONS[@]}"; do
  for codename in bullseye bookworm trixie jammy noble; do
    case "$codename" in
      bullseye|bookworm|trixie) flavor=debian ;;
      jammy|noble)              flavor=ubuntu ;;
    esac
    url="https://repo.mongodb.org/apt/${flavor}/dists/${codename}/mongodb-org/${v}/Release"
    code=$(probe "$url")
    printf "%s\t%s/%s\t%s\t%s\n" "$v" "$flavor" "$codename" "any" "$code"
  done
done

# RHEL/Rocky/Alma (yum)
for v in "${MONGO_VERSIONS[@]}"; do
  for relver in 8 9 10; do
    for arch in x86_64 aarch64; do
      url="https://repo.mongodb.org/yum/redhat/${relver}/mongodb-org/${v}/${arch}/RPMS/"
      code=$(probe "$url")
      printf "%s\t%s/%s\t%s\t%s\n" "$v" "redhat" "$relver" "$arch" "$code"
    done
  done
done
