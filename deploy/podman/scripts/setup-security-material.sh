#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Generate local registry TLS material and Shirudo operator signing material.
set -Eeuo pipefail
umask 077

SHIRUDO="${SHIRUDO:-shirudo}"
KEYS_DIR="${KEYS_DIR:-$HOME/.config/shirudo/keys}"
REGISTRY_DIR="${REGISTRY_DIR:-$(pwd)/secrets/registry}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost}"
REGISTRY_IP="${REGISTRY_IP:-127.0.0.1}"
CERT_DAYS="${CERT_DAYS:-365}"

die() { printf 'setup-security-material: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

need openssl
need "$SHIRUDO"
[[ "$CERT_DAYS" =~ ^[0-9]+$ ]] && (( CERT_DAYS >= 1 && CERT_DAYS <= 825 )) || die "CERT_DAYS must be between 1 and 825"
[[ "$REGISTRY_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "REGISTRY_HOST must be a DNS name"
[[ "$REGISTRY_IP" =~ ^[0-9A-Fa-f:.]+$ ]] || die "REGISTRY_IP must be an IP address"

mkdir -p "$REGISTRY_DIR" "$(dirname "$KEYS_DIR")"
chmod 700 "$REGISTRY_DIR" "$(dirname "$KEYS_DIR")"

TLS_KEY="$REGISTRY_DIR/server.key"
TLS_CERT="$REGISTRY_DIR/server.crt"
SIGNING_KEY="$KEYS_DIR/signing_key.pem"
SIGNING_CERT="$KEYS_DIR/cert.der"

[[ ! -e "$TLS_KEY" && ! -e "$TLS_CERT" ]] || die "registry TLS files already exist; refusing to overwrite $REGISTRY_DIR"
[[ ! -e "$SIGNING_KEY" && ! -e "$SIGNING_CERT" ]] || die "Shirudo signing material already exists; refusing to overwrite $KEYS_DIR"

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout "$TLS_KEY" -out "$TLS_CERT" -days "$CERT_DAYS" \
  -subj "/CN=$REGISTRY_HOST" \
  -addext "subjectAltName=DNS:$REGISTRY_HOST,IP:$REGISTRY_IP" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign"
chmod 600 "$TLS_KEY" "$TLS_CERT"

# Shirudo genkey creates its native ML-DSA-87 PEM key and DER certificate.
"$SHIRUDO" genkey --keys-dir "$KEYS_DIR"
[[ -f "$SIGNING_KEY" && -f "$SIGNING_CERT" ]] || die "shirudo genkey did not create signing_key.pem and cert.der"
[[ "$(stat -c '%a' "$SIGNING_KEY")" == 600 ]] || die "signing key mode must be exactly 0600"
[[ "$(stat -c '%a' "$SIGNING_CERT")" == 600 ]] || die "signing certificate mode must be exactly 0600"

printf '\nCreated security material; private key contents are not displayed.\n'
printf 'Registry CA certificate: %s\n' "$(realpath "$TLS_CERT")"
printf 'Registry TLS private key: %s (secret)\n' "$(realpath "$TLS_KEY")"
printf 'Shirudo signing key: %s (secret)\n' "$(realpath "$SIGNING_KEY")"
printf 'Shirudo signing certificate: %s\n' "$(realpath "$SIGNING_CERT")"
printf '\nShirudo signer SPKI fingerprint:\n'
"$SHIRUDO" bpm key fingerprint "$SIGNING_CERT"
printf '\nExport these values in the operator shell:\n'
printf 'export KEYS_DIR=%q\n' "$(realpath "$KEYS_DIR")"
printf 'export CA_CERT=%q\n' "$(realpath "$TLS_CERT")"
