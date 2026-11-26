# Container workload fixtures

| Directory | Runtime/build | Container approach |
|---|---|---|
| `python-app` | CPython / pip | Python runtime image |
| `workloads/node` | Node.js / npm | Non-root Node runtime |
| `workloads/typescript` | TypeScript / Node.js | Compile TS, run JS |
| `workloads/vite` | Vite / Node.js | Build static assets, serve with Nginx |
| `workloads/c` | C / GCC | Static native binary, scratch runtime |
| `workloads/go` | Go | Static Go binary, scratch runtime |
| `workloads/rust` | Rust / Cargo | Release binary, minimal Alpine runtime |

These are small smoke-test fixtures, not production applications. Vite is built as static assets and served by Nginx, not run as a development server.

Run `scripts/scan-all-workloads.sh` from `deploy/podman`. It builds each image, writes SPDX SBOM and Trivy JSON reports, and fails if a build fails or HIGH/CRITICAL findings are reported.

For production, pin base images by digest; generate genuine lockfiles (`npm install --package-lock-only`, `cargo generate-lockfile`, `go mod tidy`) and use locked install modes; build reproducibly; keep toolchains out of runtime images; run non-root; drop capabilities; and review scanner findings as evidence rather than proof of exploitability.
