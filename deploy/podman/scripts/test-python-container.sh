#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-localhost/shirudo-python-demo:local}"
NAME="shirudo-python-smoke-$RANDOM"

cleanup() { podman rm --force "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

podman image exists "$IMAGE" || {
  podman build -f "$ROOT/python-app/Containerfile" -t "$IMAGE" "$ROOT/python-app"
}
podman run --detach --name "$NAME" --publish 127.0.0.1::8080 "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
  PORT="$(podman port "$NAME" 8080/tcp | awk -F: 'NR==1 {print $NF}')"
  if [[ -n "$PORT" ]] && curl --fail --silent "http://127.0.0.1:$PORT/healthz" >/dev/null; then
    curl --fail --silent "http://127.0.0.1:$PORT/" | grep -q 'shirudo-python-demo'
    echo "PASS: Python container smoke test"
    exit 0
  fi
  sleep 1
done
podman logs "$NAME" >&2 || true
echo "FAIL: Python container did not become healthy" >&2
exit 1
