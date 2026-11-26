# Shirudo Podman Compose support stack

This project provisions operator-side support services: an OCI registry, ClickHouse and an OTLP collector. It also includes a sample Python workload, image scanning/SBOM scripts, and guarded Shirudo operator lifecycle helpers.

**It does not install the patched target kernel, Shirudo initrd, signed BPF loaders or TPM runtime.** Production enforcement requires a separate supported target booted with the Shirudo kernel and TPM 2.0.

## Start the support stack

Prepare a loopback-only registry certificate:

```bash
mkdir -p secrets/registry
chmod 700 secrets secrets/registry
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout secrets/registry/server.key -out secrets/registry/server.crt \
  -days 365 -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyCertSign,cRLSign'
chmod 600 secrets/registry/server.key
chmod 644 secrets/registry/server.crt
cp .env.example .env
podman compose --env-file .env config
podman compose --env-file .env up -d
```

Registry, ClickHouse and OTLP ports are loopback-bound by default. Do not expose this unauthenticated lab registry or ClickHouse publicly.

## Python workload assessment

Install Trivy on the operator machine. Build, smoke-test, scan and produce an SPDX SBOM:

```bash
make python-test
make python-scan
```

For a specific advisory, prepare a review packet:

```bash
./scripts/python-vulnerability-workflow.sh CVE-YYYY-NNNN
```

The packet includes an SBOM, scanner report and review checklist.

## Shirudo operator workflow

See [scripts/README.md](scripts/README.md). Scripts cover operator CLI preflight, key-file checks, building a valid Beefile package, pushing to an OCI registry, publisher fingerprint verification, guarded installation, status inspection and attestation export.

Do not place signing keys in the repository, Compose containers or environment variables. Keep them in a protected operator environment.

## Python-specific limitation

The documented Shirudo userspace upatch implementation is Java-agent based. A Python dependency CVE does not automatically have a corresponding Shirudo upatch. Identify whether the flaw is in a dependency, CPython, a native extension, the kernel interface, or application logic. Upgrade the affected package/image as the permanent fix. Only author a Shirudo shield when a specific supported mitigation can be implemented, tested and signed.

## Podman and SELinux

- Podman with a compatible Compose provider.
- `:Z` is used on local certificate/config bind mounts for SELinux.
- Compose services do not request privileged mode, host PID/network namespaces, `/sys`, `/lib/modules` or BPF capabilities.
- The collector currently exports to debug logs; it is not yet wired to Shirudo's full quote-verification backend.
- Image tags are lab defaults; pin verified digests before production.

Upstream requirements:
https://docs.shirudo.dev/operate/plan/system-requirements.html
https://docs.shirudo.dev/operate/deploy/deployment-checklist.html
