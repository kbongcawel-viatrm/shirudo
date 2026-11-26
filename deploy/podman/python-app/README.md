# Python workload example

A deliberately small, non-vulnerable Python service used to validate image
build, SBOM and vulnerability scanning workflows. It is not an exploit
fixture and should not be exposed to the public Internet.

Build and run through the parent Podman Compose file. The app uses a
non-root UID and a health endpoint. Pin the base image by digest and lock
all dependencies with hashes for production use.
