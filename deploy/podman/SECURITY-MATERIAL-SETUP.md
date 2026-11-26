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

## 3. Embed the primary signer in the initial runtime image\n\nWith the target Shirudo binary, runtime bootstrap configuration and config-verification certificate available, run:\n\n~~~bash\n./deploy/podman/scripts/setup-security-material.sh build-runtime \\\n  ./build/shirudo-target \\\n  ./runtime.conf \\\n  ./config-verification-cert.der \\\n  ./out/shirudo-runtime\n~~~\n\nThis invokes shirudo-gen-runtime with the generated primary cert.der as --cert and the supplied config verification certificate as --config-cert. The command builds a runtime image; it does not build the kernel/UKI or deploy/reboot the target. Review the output and complete the documented boot integration steps before provisioning. The config signing key may be the same key or a separate operator key, depending on your trust design.\n\n## 4. Generate and vouch a standby signer

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