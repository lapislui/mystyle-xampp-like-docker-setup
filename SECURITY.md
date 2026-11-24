# Security Policy

## Scope & Purpose

This repository provides a **local development stack** designed for convenient offline and development use.

### Important Notice

- **Default Credentials:** The default credentials (`root` / `root`, `dev` / `dev`, `admin` / `admin`) are intended solely for local environments.
- **Network Binding:** By default, services bind to `127.0.0.1` (loopback). Do not expose these containers directly to public or untrusted networks without modifying default credentials, disabling debugging tools (like Xdebug), and securing exposed ports.
- **Docker Socket:** The optional Jenkins container mounts the Docker socket for CI container workflows, granting root-equivalent privileges within the host Docker daemon. Keep it restricted to trusted local machines.

## Reporting Security Concerns

If you discover a security concern regarding the container definitions or build scripts, please open an issue or contact the project maintainers with details, reproduction steps, and suggested remediations.
