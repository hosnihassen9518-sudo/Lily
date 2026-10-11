# Local Containers Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Package the backend, broker, and admin portal for one-command Ubuntu LAN deployment with configurable published ports.

**Architecture:** Docker Compose connects three services by DNS name and starts dependent services after health checks. Named volumes preserve SQLite/music and MQTT state. Nginx serves the admin SPA and proxies its same-origin API requests.

**Tech Stack:** Python 3.12, FastAPI/Uvicorn, Mosquitto 2, Node 22, Nginx, Docker Compose.

**Spec:** ../specs/2026-10-11-local-containers-design.md

## Constraints and review focus

- Keep internal ports 80, 8000, and 1883 fixed; expose configurable host ports.
- Require root environment JWT secret and admin password. Exclude environment files, caches, databases, and dependency directories from image contexts.
- One backend worker; no development reload. Run backend as a non-root user with writable persistent storage.
- Preserve `/api/v1` proxy paths, support SPA fallback, and resolve backend DNS after recreation.
- Anonymous MQTT matches current firmware; document LAN-only scope and initial fresh database behavior.
- Do not include unrelated existing worktree changes in the commit.

## Task 1: Container packaging and orchestration

- [x] Add backend and admin Dockerfiles and allowlist Docker ignore files.
- [x] Add Nginx and Mosquitto configurations, Compose services, health checks, persistent volumes, and environment template.
- [x] Validate missing-secret failure and validate default/custom ports using `docker compose config`.
- [x] Build portal assets with the relative API base and inspect generated assets.
- [x] Check Docker engine availability: unavailable, so image builds and runtime verification remain unperformed and must be reported.

## Task 2: Delivery

- [x] Add Ubuntu setup, endpoint, restart, backup, and troubleshooting documentation.
- [x] Review staged files for secrets and unrelated changes; run `git diff --check`. Independent review found no actionable defects.
- [ ] Commit only deployment artifacts and push to `main` as authorized.
