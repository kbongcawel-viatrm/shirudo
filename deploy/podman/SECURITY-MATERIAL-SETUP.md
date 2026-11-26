# Shirudo security material: generation and signer enrollment

## Scope

This procedure creates registry TLS material and Shirudo operator signing keys. It also automates enrollment preparation for an additional (standby) BPF signer by generating its key, obtaining a vouch from the primary signer, and placing the certificate/vouch pair into a config-image source tree.

**Important:** copying files does not complete target enrollment. The target BPF keyring is sealed at boot. On a target using a signed config image, adding a signer requires building a new signed config image, staging it on the target, and rebooting during a planned maintenance window. The script does not remotely stage or reboot a target.

## 1. Prerequisites

On the operator host install the Shirudo operator CLI, OpenSSL 1.1.1 or newer, Podman and a compatible Compose provider. Check:

~~~bash
shirudo version
shirudo genkey --help
shirudo keys vouch --help
shirudo-gen-image --help
~~~

Shirudo genkey creates an ML-DSA-87 PEM private key (signing_key.pem, mode 0600) and self-signed DER X.509 certificate (cert.der, mode 0600). The private key stays on the operator host.

## 2. Generate registry TLS and primary Shirudo signer

From the repository root:

~~~bash
chmod +x deploy/podman/scripts/setup-security-material.sh
KEYS_DIR="$HOME/.config/shirudo/keys" \
REGISTRY_DIR="$PWD/deploy/podman/secrets/registry" \
REGISTRY_HOST=localhost REGISTRY_IP=127.0.0.1 \
./deploy/podman/scripts/setup-security-material.sh
~~~

Generated files:

~~~text
deploy/podman/secrets/registry/server.crt  # Public registry CA certificate
deploy/podman/secrets/registry/server.key  # Private TLS key, mode 0600
~/.config/shirudo/keys/signing_key.pem     # Private ML-DSA-87 key, mode 0600
~/.config/shirudo/keys/cert.der            # Public signing certificate, DER
~~~

The registry certificate SAN defaults to localhost and 127.0.0.1. Set REGISTRY_HOST and REGISTRY_IP to the actual registry identity before generation if clients use another name/address. The script refuses to overwrite existing keys.

The primary signer is the initial trust anchor. Its certificate must be embedded as the initial BPF signer in the runtime image. Use the helper's build-runtime mode when you have the target binary, runtime bootstrap config and config-verification certificate.

## 3. Embed the primary signer in the initial runtime image

With the target Shirudo binary, runtime bootstrap configuration and config-verification certificate available, run:

~~~bash
./deploy/podman/scripts/setup-security-material.sh build-runtime \\
  ./build/shirudo-target \\
  ./runtime.conf \\
  ./config-verification-cert.der \\
  ./out/shirudo-runtime
~~~

This invokes shirudo-gen-runtime with the generated primary cert.der as --cert and the supplied config verification certificate as --config-cert. The command builds a runtime image; it does not build the kernel/UKI or deploy/reboot the target. Review the output and complete the documented boot integration steps before provisioning. The config signing key may be the same key or a separate operator key, depending on your trust design.

## 4. Generate and vouch a standby signer

Use the existing config-image source tree for the target. Do not use an empty directory; it must contain a valid Shirudo config tree.

~~~bash
export KEYS_DIR="$HOME/.config/shirudo/keys"
./deploy/podman/scripts/setup-security-material.sh enroll-standby \
  "$HOME/.config/shirudo/standby-keys" \
  ./config-root
~~~

This generates the standby ML-DSA-87 key, signs a vouch for its certificate using the primary signer, and adds the matching files to config-root/keys/trusted/: <SPKI-fingerprint>.der and <SPKI-fingerprint>.vouch.

Optionally build the signed config image in the same operation:

~~~bash
./deploy/podman/scripts/setup-security-material.sh enroll-standby \
  "$HOME/.config/shirudo/standby-keys" \
  ./config-root \
  ./out/config-with-standby
~~~

This invokes shirudo-gen-image --source <config-root> --output <prefix> --keys-dir <primary-keys-dir> --kind config. The config source must be valid and complete. Review the generated image and signature before delivery.

## 5. Stage and activate on the target

Transfer the generated config image to the supported target through the approved deployment channel. On the target:

~~~bash
sudo shirudo image stage <config-image-prefix>
sudo shirudo image status
~~~

Confirm the staged image is correct, then reboot during a planned maintenance window. After reboot:

~~~bash
sudo shirudo image status
sudo shirudo keys
~~~

Verify the standby fingerprint appears in the trusted set and frozen .bpf keyring. A live shirudo keys add or shirudo bpm key add is not the enrollment path for a target with an active config image; the signed config and reboot are required.

## 6. Configure registry transport

~~~bash
export CA_CERT="$PWD/deploy/podman/secrets/registry/server.crt"
export BPM_OCI_CA_FILE="$CA_CERT"
export REGISTRY="oci://127.0.0.1:15444/shirudo"
~~~

CA_CERT is the public registry CA certificate, not either private key and not the Shirudo signing certificate.

## 7. Backup and rotation

- Back up each operator key directory (signing_key.pem plus matching cert.der) to encrypted offline storage.
- Record SPKI fingerprints through a separate trusted channel.
- Do not use shirudo genkey --force as a casual reset. Rotation requires a planned trust overlap and config/runtime transition.
- Registry TLS rotation is independent from package-signer rotation.
- If a signer is compromised, stop using it and follow the documented revocation process.

## 8. Git hygiene

Generated registry secrets and operator key directories must never be committed. Check:

~~~bash
git status --short
git check-ignore -v deploy/podman/secrets/registry/server.key
~~~

Never paste private key contents into chat, issues, PRs, logs, or shell transcripts.

## Official Shirudo references

- [Manage signing keys](https://docs.shirudo.dev/operate/maintain/keys.html)
- [shirudo keys CLI](https://docs.shirudo.dev/reference/cli/keys.html)
- [BPM key commands](https://docs.shirudo.dev/reference/cli/bpm.html)
- [Config images and enrollment](https://docs.shirudo.dev/internals/config-images.html)
- [File modes and key paths](https://docs.shirudo.dev/reference/files.html)

## Validation

Run the script on the operator host with the exact installed Shirudo version. The GitHub environment cannot generate your private keys or enroll your target. The script prepares the local signer and config source; staging, reboot and post-boot verification remain target-side operations.

## 9. End-to-end operator runbook

This section collects the commands in execution order. Run them on the operator host unless explicitly marked **target-side**. Replace example paths and hostnames with real deployment values.

### 9.1 Preflight

From the repository root:

~~~bash
command -v shirudo
command -v openssl
command -v podman
shirudo version
shirudo genkey --help
shirudo keys vouch --help
shirudo-gen-runtime --help
shirudo-gen-image --help
~~~

Do not continue if the command syntax or installed version differs from the documented interface. The project helper is a wrapper; the installed Shirudo release is authoritative.

### 9.2 Generate credentials

~~~bash
chmod +x deploy/podman/scripts/setup-security-material.sh

KEYS_DIR="$HOME/.config/shirudo/keys" \
REGISTRY_DIR="$PWD/deploy/podman/secrets/registry" \
REGISTRY_HOST=localhost \
REGISTRY_IP=127.0.0.1 \
./deploy/podman/scripts/setup-security-material.sh
~~~

Record the primary signer's SPKI fingerprint printed by the script. Transfer that fingerprint to the target provisioning/trust process through a separate trusted channel. Never transfer the private signing key to the target.

If the command stops because a key directory or TLS file already exists, do not delete it automatically. Inspect and back up the existing material before deciding whether to reuse it.

### 9.3 Verify permissions and certificate contents

~~~bash
KEYS_DIR="$HOME/.config/shirudo/keys"
REGISTRY_DIR="$PWD/deploy/podman/secrets/registry"

test -s "$REGISTRY_DIR/server.crt"
test -s "$REGISTRY_DIR/server.key"
test -s "$KEYS_DIR/signing_key.pem"
test -s "$KEYS_DIR/cert.der"

stat -c '%a %n' \
  "$REGISTRY_DIR/server.key" \
  "$KEYS_DIR/signing_key.pem" \
  "$KEYS_DIR/cert.der"

openssl x509 -in "$REGISTRY_DIR/server.crt" \
  -noout -subject -issuer -dates -ext subjectAltName
openssl x509 -inform DER -in "$KEYS_DIR/cert.der" \
  -noout -subject -issuer
shirudo bpm key fingerprint "$KEYS_DIR/cert.der"
~~~

Expected private-key mode is 600. The generated certificate files are also restricted to mode 600 by this helper. Do not use `cat`, `less`, or shell tracing on private key files.

### 9.4 Start the local support stack

~~~bash
cd deploy/podman
cp .env.example .env
podman compose --env-file .env config
podman compose --env-file .env up -d
podman compose ps
~~~

Check the registry endpoint and TLS certificate:

~~~bash
openssl s_client -connect 127.0.0.1:15444 \
  -CAfile secrets/registry/server.crt \
  -verify_return_error </dev/null
~~~

A successful TLS check should report certificate verification success. If clients connect using a different DNS name or IP, regenerate the registry certificate with that name/address in its SAN and configure the client to trust that CA. Do not disable certificate verification.

### 9.5 Export operator environment

Run from the repository root (adjust path if your working directory differs):

~~~bash
export KEYS_DIR="$HOME/.config/shirudo/keys"
export CA_CERT="$PWD/deploy/podman/secrets/registry/server.crt"
export BPM_OCI_CA_FILE="$CA_CERT"
export REGISTRY="oci://127.0.0.1:15444/shirudo"

./deploy/podman/scripts/shirudo-operator.sh version
./deploy/podman/scripts/shirudo-operator.sh keys-check
~~~

### 9.6 Build initial runtime image

**Operator-side preparation.** Obtain the target-compatible Shirudo binary, bootstrap configuration, and config-verification certificate from the approved build/provisioning process. Verify the exact `shirudo-gen-runtime --help` syntax for the installed release.

Example using the helper:

~~~bash
./deploy/podman/scripts/setup-security-material.sh build-runtime \
  ./build/shirudo-target \
  ./runtime.conf \
  ./config-verification-cert.der \
  ./out/shirudo-runtime
~~~

Inspect the output and complete the upstream boot-image/UKI integration steps. This helper does not build the kernel, create a UKI, install a bootloader entry, or reboot a target.

### 9.7 Prepare standby signer enrollment

Use a real, existing config-image source tree for the target. It must be a complete and valid Shirudo configuration, not an empty directory.

~~~bash
./deploy/podman/scripts/setup-security-material.sh enroll-standby \
  "$HOME/.config/shirudo/standby-keys" \
  ./config-root \
  ./out/config-with-standby
~~~

The helper generates a standby signer, creates a vouch using the primary signer, places the fingerprint-named certificate and vouch under `config-root/keys/trusted/`, and invokes `shirudo-gen-image` to build a signed config image.

Review the generated trust files, image metadata and signature. Preserve the standby private key separately with the same controls as the primary key.

### 9.8 Manual target-side staging and activation

These steps are intentionally manual and must be performed on the supported Shirudo target during a planned maintenance window.

1. Transfer the generated config image and required companion files using the approved deployment channel.
2. Verify the image provenance, expected root hash and signer before staging.
3. Stage the config image:

~~~bash
sudo shirudo image stage <config-image-prefix>
sudo shirudo image status
~~~

4. Confirm the staged image is the intended image and that rollback/recovery is available.
5. Reboot the target during the maintenance window.
6. After reboot, verify active image and signer trust:

~~~bash
sudo shirudo image status
sudo shirudo keys
~~~

7. Confirm the standby signer fingerprint is present in the trusted set and frozen BPF keyring. Check target health and workload behavior before declaring enrollment complete.

Do not use a live key-add command as a substitute for signed config-image enrollment on a target whose BPF keyring is sealed at boot. Do not automate the reboot.

### 9.9 Package lifecycle after target provisioning

Only use a valid, reviewed Shirudo Beefile and supported upatch artifacts. The sample Python/Node.js/TypeScript/Vite/C/Go/Rust workloads are image-scan fixtures, not automatically valid Shirudo upatches.

Check the installed package CLI syntax first:

~~~bash
shirudo bpm build --help
shirudo bpm push --help
shirudo bpm info --help
shirudo bpm key fingerprint --help
~~~

The helper commands are:

~~~bash
./deploy/podman/scripts/shirudo-operator.sh build ./path/to/package 1.0.0
./deploy/podman/scripts/shirudo-operator.sh push ./path/to/package 1.0.0
./deploy/podman/scripts/shirudo-operator.sh inspect <oci-package-reference>
./deploy/podman/scripts/shirudo-operator.sh verify-key \
  <oci-package-reference> <trusted-sha256-fingerprint>
~~~

Before installation, compare the package publisher fingerprint with the independently recorded trusted fingerprint. Follow the target's provisioning mode and upstream installation workflow. Do not assume a live `bpm key add` is valid for a config-image-managed target.

### 9.10 Post-install verification

On the target, check the active config image, signer trust, Shirudo status and installed upatches:

~~~bash
sudo shirudo image status
sudo shirudo keys
sudo shirudo status
sudo shirudo upatch list
~~~

Export attestation only if the target CLI supports it in the installed version and protect the resulting file:

~~~bash
sudo shirudo attest > shirudo-attestation.json
chmod 600 shirudo-attestation.json
~~~

Validate the attestation using the trusted verifier process; generating an attestation file alone does not establish that its claims are valid.

### 9.11 Stop the lab

From `deploy/podman`:

~~~bash
podman compose down
~~~

This stops containers but retains named volumes. Use `podman compose down -v` only when intentionally deleting registry and ClickHouse persistent data.

## 10. Execution status and safety boundary

The commands above are documented procedures, not evidence that they have already been executed. The repository PR contains the scripts and documentation only. Actual key generation, registry TLS validation, image generation, target staging, reboot, enrollment verification and package installation must be performed and recorded on the real operator/target systems.

Never commit the generated `server.key`, `signing_key.pem`, standby private keys, registry credentials, or attestation files.
