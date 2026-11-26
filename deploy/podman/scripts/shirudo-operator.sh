#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Guarded operator helper for Shirudo package lifecycle.
# Run against an installed Shirudo operator CLI. This script does not create
# arbitrary shields or auto-deploy them to production targets.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SHIRUDO="${SHIRUDO:-shirudo}"
KEYS_DIR="${KEYS_DIR:-$HOME/.config/shirudo/keys}"
REGISTRY="${REGISTRY:-oci://127.0.0.1:15444/shirudo}"
PACKAGE="${PACKAGE:-}"
VERSION="${VERSION:-}"
TARGET="${TARGET:-}"
CA_CERT="${CA_CERT:-}"

die() { echo "shirudo-operator: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
usage() {
  cat <<'EOF'
Usage:
  shirudo-operator.sh version
  shirudo-operator.sh keys-check
  shirudo-operator.sh build <Beefile-or-directory> <version>
  shirudo-operator.sh push <package-dir> <version>
  shirudo-operator.sh inspect <oci-package-reference>
  shirudo-operator.sh verify-key <oci-package-reference> <trusted-sha256-fingerprint>
  shirudo-operator.sh install <oci-package-reference> <trusted-sha256-fingerprint>
  shirudo-operator.sh status
  shirudo-operator.sh attest [output.json]

Environment:
  SHIRUDO, KEYS_DIR, REGISTRY, CA_CERT, TARGET
EOF
}
[[ $# -ge 1 ]] || { usage; exit 2; }
cmd=$1; shift

case "$cmd" in
  version)
    need "$SHIRUDO"
    "$SHIRUDO" version
    ;;
  keys-check)
    [[ -d "$KEYS_DIR" ]] || die "keys directory not found: $KEYS_DIR"
    [[ -s "$KEYS_DIR/signing_key.pem" ]] || die "missing operator signing_key.pem"
    [[ -s "$KEYS_DIR/cert.pem" || -s "$KEYS_DIR/signing_cert.pem" ]] ||
      die "operator certificate not found; consult Shirudo key-management docs"
    chmod 700 "$KEYS_DIR"
    chmod 600 "$KEYS_DIR/signing_key.pem"
    echo "Operator key files exist; verify fingerprint and offline backup separately."
    ;;
  build)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    need "$SHIRUDO"
    src=$(realpath "$1")
    version=$2
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] ||
      die "version must be semver-like"
    [[ -e "$src" ]] || die "source not found: $src"
    (cd "$(dirname "$src")" && "$SHIRUDO" bpm build "$src" --version "$version" --keys-dir "$KEYS_DIR")
    ;;
  push)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    need "$SHIRUDO"
    src=$(realpath "$1"); version=$2
    [[ -f "$src/Beefile" ]] || die "package directory must contain Beefile"
    [[ "$REGISTRY" == oci://* ]] || die "REGISTRY must be oci://..."
    [[ -s "$KEYS_DIR/signing_key.pem" ]] || die "operator signing key missing"
    [[ -n "$CA_CERT" && -r "$CA_CERT" ]] || die "set CA_CERT to trusted registry CA"
    export BPM_OCI_CA_FILE="$CA_CERT"
    "$SHIRUDO" bpm push "$src" "$REGISTRY/$(basename "$src"):$version" --keys-dir "$KEYS_DIR"
    ;;
  inspect)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    need "$SHIRUDO"
    "$SHIRUDO" bpm info "$1"
    ;;
  verify-key)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    need "$SHIRUDO"
    ref=$1; expected=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "expected fingerprint must be 64 hex characters"
    output=$("$SHIRUDO" bpm key fingerprint "$ref")
    printf '%s\n' "$output"
    printf '%s\n' "$output" | grep -Fqi "$expected" ||
      die "publisher fingerprint mismatch; refusing install"
    ;;
  install)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    need "$SHIRUDO"
    ref=$1; expected=$2
    "$0" verify-key "$ref" "$expected"
    echo "About to install signed package: $ref"
    read -r -p "Type INSTALL to continue: " answer
    [[ "$answer" == INSTALL ]] || die "cancelled"
    sudo "$SHIRUDO" bpm key add "$ref"
    sudo "$SHIRUDO" bpm install "$ref"
    sudo "$SHIRUDO" upatch list
    ;;
  status)
    need "$SHIRUDO"
    sudo "$SHIRUDO" status
    sudo "$SHIRUDO" upatch list
    ;;
  attest)
    need "$SHIRUDO"
    out=${1:-shirudo-attestation.json}
    sudo "$SHIRUDO" attest > "$out"
    chmod 600 "$out"
    echo "Attestation written to $out; verify it with the trusted operator workflow."
    ;;
  *) usage; exit 2 ;;
esac
