#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
#
# Creates a review packet for a Python container vulnerability.
# It intentionally DOES NOT generate or install an upatch. A valid Shirudo
# shield must be engineered for the vulnerable kernel/application code path,
# tested against the exact affected build, and signed by the trusted operator.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VULN_ID="${1:-}"
IMAGE="${IMAGE:-localhost/shirudo-python-demo:local}"
OUT="${OUT:-$ROOT/artifacts/candidate-${VULN_ID:-unknown}}"

if [[ ! "$VULN_ID" =~ ^(CVE-[0-9]{4}-[0-9]{4,}|GHSA-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4})$ ]]; then
  echo "Usage: $0 CVE-YYYY-NNNN | GHSA-xxxx-xxxx-xxxx" >&2
  exit 2
fi

command -v podman >/dev/null 2>&1 || { echo "podman required" >&2; exit 127; }
command -v trivy >/dev/null 2>&1 || { echo "trivy required" >&2; exit 127; }

mkdir -p "$OUT"
podman image exists "$IMAGE" || { echo "Image not found: $IMAGE" >&2; exit 1; }

trivy image --scanners vuln --format spdx-json \
  --output "$OUT/sbom.spdx.json" "$IMAGE"
trivy image --scanners vuln --format json \
  --output "$OUT/scan.json" "$IMAGE"

cat > "$OUT/SHIELD-REVIEW.md" <<EOF
# Shirudo shield review packet

- Vulnerability: $VULN_ID
- Image: $IMAGE
- Generated: $(date -u +%FT%TZ)
- SBOM: sbom.spdx.json
- Scanner output: scan.json

## Required engineering review

1. Confirm the advisory applies to the exact package and runtime build.
2. Identify the vulnerable execution path and whether a kernel hook or
   supported application upatch can safely mediate it.
3. Do not assume Python bytecode or a Python package vulnerability maps to a
   generic BPF shield. Shirudo upatches are purpose-built.
4. Reproduce the issue in an isolated target running the supported Shirudo
   kernel and TPM configuration.
5. Write positive and negative regression tests, including normal workload
   behaviour and performance.
6. Review and sign the final Beefile/package with the trusted operator key.
7. Deploy to a canary target, verify TPM evidence and monitor before rollout.
8. Patch/upgrade the Python dependency and rebuild the image. Remove the
   temporary shield only after the permanent fix is validated.

## Deployment state

NOT GENERATED • NOT SIGNED • NOT DEPLOYED

This packet contains evidence and review instructions only.
EOF

echo "Review packet created: $OUT"
