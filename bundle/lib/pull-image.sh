#!/usr/bin/env bash
# Pull linux/amd64 image as a single-platform ref (required for docker save on arm64 builders).

set -euo pipefail

amd64_digest() {
  local image="$1"
  docker buildx imagetools inspect "$image" 2>/dev/null | awk '
    /Name:.*@sha256:/ { last = $0 }
    /Platform:[[:space:]]+linux\/amd64/ {
      if (match(last, /sha256:[a-f0-9]{64}/)) {
        print substr(last, RSTART, RLENGTH)
        exit
      }
    }
  '
}

pull_amd64_image() {
  local image="$1"
  local digest repo_tag

  digest="$(amd64_digest "$image" || true)"
  if [[ -n "$digest" ]]; then
    repo_tag="${image%@*}"
    docker pull "${repo_tag}@${digest}"
    docker tag "${repo_tag}@${digest}" "$image" 2>/dev/null || true
    echo "$image"
    return 0
  fi

  docker pull --platform linux/amd64 "$image"
  echo "$image"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  pull_amd64_image "$@"
fi
