#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Build and scan Python, Node, TypeScript, Vite, C, Go and Rust images.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/artifacts}"
SEVERITY="${SEVERITY:-HIGH,CRITICAL}"
mkdir -p "$OUT"
for cmd in podman trivy; do command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 127; }; done
declare -A paths=([python]="$ROOT/python-app" [node]="$ROOT/workloads/node" [typescript]="$ROOT/workloads/typescript" [vite]="$ROOT/workloads/vite" [c]="$ROOT/workloads/c" [go]="$ROOT/workloads/go" [rust]="$ROOT/workloads/rust")
failed=0
for lang in python node typescript vite c go rust; do
  context="${paths[$lang]}"
  image="localhost/shirudo-$lang-demo:scan"
  echo "==> Building $lang"
  if ! podman build --file "$context/Containerfile" --tag "$image" "$context"; then echo "BUILD FAILED: $lang" >&2; failed=1; continue; fi
  trivy image --scanners vuln --format spdx-json --output "$OUT/$lang.spdx.json" "$image"
  trivy image --scanners vuln --format json --output "$OUT/$lang.vulnerabilities.json" "$image"
  if ! trivy image --scanners vuln --severity "$SEVERITY" --exit-code 1 "$image"; then echo "VULNERABILITY GATE FAILED: $lang" >&2; failed=1; fi
done
echo "Reports: $OUT"
exit "$failed"
