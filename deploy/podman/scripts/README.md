# Operator scripts

All scripts are intentionally gated. They never create a generic Python
runtime shield or automatically deploy an unreviewed kernel upatch.

## Python image assessment

```bash
make -C deploy/podman python-test
make -C deploy/podman python-scan
./deploy/podman/scripts/python-vulnerability-workflow.sh CVE-YYYY-NNNN
```

The scan generates an SPDX SBOM and Trivy report. The review packet documents
the affected image, advisory, test and approval requirements.

## Shirudo operator lifecycle

Install the Shirudo operator CLI using the upstream release/build guide. Keep
the signing key in a protected operator environment, not in Podman or Git.

```bash
export KEYS_DIR="$HOME/.config/shirudo/keys"
export REGISTRY="oci://127.0.0.1:15444/shirudo"
export CA_CERT="$PWD/deploy/podman/secrets/registry/server.crt"

./deploy/podman/scripts/shirudo-operator.sh version
./deploy/podman/scripts/shirudo-operator.sh keys-check
./deploy/podman/scripts/shirudo-operator.sh inspect oci://registry.example/shirudo/package:version
./deploy/podman/scripts/shirudo-operator.sh verify-key oci://registry.example/shirudo/package:version <trusted-sha256-fingerprint>
```

For a package containing a valid, reviewed Beefile:

```bash
./deploy/podman/scripts/shirudo-operator.sh build ./path/to/package 1.0.1
./deploy/podman/scripts/shirudo-operator.sh push ./path/to/package 1.0.1
```

Check the exact syntax for your fork's CLI with `shirudo bpm --help` before
use; Shirudo is pre-release and CLI interfaces can change.

On a separately booted, supported Shirudo target:

```bash
./deploy/podman/scripts/shirudo-operator.sh install \
  oci://registry.example/shirudo/package:version <trusted-sha256-fingerprint>
./deploy/podman/scripts/shirudo-operator.sh status
./deploy/podman/scripts/shirudo-operator.sh attest target-attestation.json
```

The install command verifies the publisher fingerprint against the trusted
value, then requires typing INSTALL. It invokes the package key import and
install commands on the target. Confirm the key-management process in the
upstream docs before production use.

## Important distinction for Python

The repository's currently documented userspace upatch support is Java-agent
based. Python packages do not automatically map to an eBPF or Shirudo
userspace upatch. For a Python CVE, first determine whether the defect is in
the Python dependency, interpreter, native extension, kernel interface, or
application logic. Usually the correct permanent fix is upgrading the
affected Python package/base image. A Shirudo shield is only appropriate
when an engineer can define and test a supported kernel/application
mitigation for the concrete vulnerability.
