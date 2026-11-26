#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
set -Eeuo pipefail
umask 077
SHIRUDO="${SHIRUDO:-shirudo}"
KEYS_DIR="${KEYS_DIR:-$HOME/.config/shirudo/keys}"
REGISTRY_DIR="${REGISTRY_DIR:-$(pwd)/secrets/registry}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost}"
REGISTRY_IP="${REGISTRY_IP:-127.0.0.1}"
CERT_DAYS="${CERT_DAYS:-365}"
die(){ printf 'setup-security-material: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
usage(){
cat <<'EOF'
Usage:
  setup-security-material.sh
  setup-security-material.sh build-runtime <target-shirudo-binary> <bootstrap-conf> <config-cert.der> <output-prefix>\n  setup-security-material.sh enroll-standby <standby-keys-dir> <config-root> [config-image-prefix]
EOF
}
ensure_primary(){
  [[ -s "$KEYS_DIR/signing_key.pem" && -s "$KEYS_DIR/cert.der" ]] || die "primary keys missing; run setup script first"
  [[ "$(stat -c '%a' "$KEYS_DIR/signing_key.pem")" == 600 ]] || die "primary signing key mode must be 0600"
}
fingerprint_hex(){
  "$SHIRUDO" bpm key fingerprint "$1" | grep -Eo '[0-9a-fA-F]{64}' | tail -n1 | tr '[:upper:]' '[:lower:]'
}
if [[ "${1:-}" == build-runtime ]]; then
  [[ $# -eq 5 ]] || { usage; exit 2; }
  need "$SHIRUDO"; need shirudo-gen-runtime; ensure_primary
  binary=$2; bootstrap=$3; config_cert=$4; output=$5
  [[ -x "$binary" ]] || die "target Shirudo binary must exist and be executable: $binary"
  [[ -f "$bootstrap" && -f "$config_cert" ]] || die "bootstrap config or config verification certificate missing"
  shirudo-gen-runtime --binary "$binary" --bootstrap-conf "$bootstrap" \
    --cert "$KEYS_DIR/cert.der" --config-cert "$config_cert" \
    --output "$output" --keys-dir "$KEYS_DIR"
  printf 'Runtime image built with primary BPF signer: %s\n' "$KEYS_DIR/cert.der"
  printf 'Review generated runtime image and UKI/boot integration before deployment.\n'
  exit 0
fi
if [[ "${1:-}" == enroll-standby ]]; then
  [[ $# -ge 3 && $# -le 4 ]] || { usage; exit 2; }
  need "$SHIRUDO"; ensure_primary
  standby_dir=$2; config_root=$3; image_prefix=${4:-}
  [[ ! -e "$standby_dir" ]] || die "standby directory exists: $standby_dir"
  [[ -d "$config_root" ]] || die "config source tree missing: $config_root"
  mkdir -p "$(dirname "$standby_dir")"
  "$SHIRUDO" genkey --keys-dir "$standby_dir"
  cert="$standby_dir/cert.der"
  [[ -s "$standby_dir/signing_key.pem" && -s "$cert" ]] || die "genkey output missing"
  [[ "$(stat -c '%a' "$standby_dir/signing_key.pem")" == 600 ]] || die "standby key mode must be 0600"
  fp=$(fingerprint_hex "$cert")
  [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || die "could not parse signer SPKI fingerprint"
  trusted="$config_root/keys/trusted"
  mkdir -p "$trusted"; chmod 700 "$standby_dir" "$trusted"
  [[ ! -e "$trusted/$fp.der" && ! -e "$trusted/$fp.vouch" ]] || die "trust entry already exists: $fp"
  "$SHIRUDO" keys vouch "$cert" -o "$trusted/$fp.vouch" --keys-dir "$KEYS_DIR"
  install -m 0644 "$cert" "$trusted/$fp.der"
  chmod 0644 "$trusted/$fp.vouch"
  printf 'Standby signer vouched. SPKI fingerprint: %s\n' "$fp"
  if [[ -n "$image_prefix" ]]; then
    need shirudo-gen-image
    shirudo-gen-image --source "$config_root" --output "$image_prefix" --keys-dir "$KEYS_DIR" --kind config
    printf 'Signed config image built: %s\n' "$image_prefix"
  fi
  printf 'Transfer config image to target; run shirudo image stage <prefix>, verify shirudo image status, then reboot in a planned window.\n'
  exit 0
fi
[[ $# -eq 0 ]] || { usage; exit 2; }
need openssl; need "$SHIRUDO"
[[ "$CERT_DAYS" =~ ^[0-9]+$ ]] && (( CERT_DAYS >= 1 && CERT_DAYS <= 825 )) || die "CERT_DAYS must be 1..825"
[[ "$REGISTRY_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid REGISTRY_HOST"
[[ "$REGISTRY_IP" =~ ^[0-9A-Fa-f:.]+$ ]] || die "invalid REGISTRY_IP"
mkdir -p "$REGISTRY_DIR" "$(dirname "$KEYS_DIR")"
chmod 700 "$REGISTRY_DIR" "$(dirname "$KEYS_DIR")"
TLS_KEY="$REGISTRY_DIR/server.key"; TLS_CERT="$REGISTRY_DIR/server.crt"
[[ ! -e "$TLS_KEY" && ! -e "$TLS_CERT" ]] || die "registry TLS files exist; refusing overwrite"
[[ ! -e "$KEYS_DIR" ]] || die "Shirudo key directory exists; refusing overwrite"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout "$TLS_KEY" -out "$TLS_CERT" -days "$CERT_DAYS" \
  -subj "/CN=$REGISTRY_HOST" \
  -addext "subjectAltName=DNS:$REGISTRY_HOST,IP:$REGISTRY_IP" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign"
chmod 600 "$TLS_KEY" "$TLS_CERT"
"$SHIRUDO" genkey --keys-dir "$KEYS_DIR"
[[ -s "$KEYS_DIR/signing_key.pem" && -s "$KEYS_DIR/cert.der" ]] || die "shirudo genkey output missing"
[[ "$(stat -c '%a' "$KEYS_DIR/signing_key.pem")" == 600 ]] || die "signing key mode must be 0600"
[[ "$(stat -c '%a' "$KEYS_DIR/cert.der")" == 600 ]] || die "certificate mode must be 0600"
printf 'Registry CA: %s\nShirudo signing key: %s (secret)\nShirudo certificate: %s\n' "$(realpath "$TLS_CERT")" "$(realpath "$KEYS_DIR/signing_key.pem")" "$(realpath "$KEYS_DIR/cert.der")"
"$SHIRUDO" bpm key fingerprint "$KEYS_DIR/cert.der"
printf 'export KEYS_DIR=%q\nexport CA_CERT=%q\n' "$(realpath "$KEYS_DIR")" "$(realpath "$TLS_CERT")"
