#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Build Python image, generate SBOM, scan image and fail on HIGH/CRITICAL.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-localhost/shirudo-python-demo:local}"
OUT="${OUT:-$ROOT/artifacts}"
mkdir -p "$OUT"

for cmd in podman trivy; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 127
  }
done

podman build --file "$ROOT/python-app/Containerfile" --tag "$IMAGE" "$ROOT/python-app"

# SPDX SBOM records OS and language package components.
trivy image --scanners vuln --format spdx-json \
  --output "$OUT/python-image.spdx.json" "$IMAGE"

# Keep a machine-readable report for CI and operator review.
trivy image --scanners vuln --format json \
  --output "$OUT/python-vulnerabilities.json" "$IMAGE"

# Gate deployment on fixable/known HIGH and CRITICAL findings.
trivy image --scanners vuln --severity HIGH,CRITICAL \
  --exit-code 1 "$IMAGE"

echo "PASS: no HIGH/CRITICAL image vulnerabilities detected."
echo "SBOM: $OUT/python-image.spdx.json"
echo "Report: $OUT/python-vulnerabilities.json"
