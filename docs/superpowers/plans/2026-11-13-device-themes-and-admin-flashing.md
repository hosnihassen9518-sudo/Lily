# Device themes and admin USB flashing Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** Use catalog presentation in the mobile app and provision or update Lily boards from the admin portal.
**Architecture:** Store presentation on the existing models. An authorized backend compiles a device-specific package, and the portal probes and writes it through Web Serial.
**Tech Stack:** FastAPI, SQLAlchemy, PlatformIO, Flutter, React, esptool-js.
**Spec:** [Approved design](../specs/2026-11-13-device-themes-and-admin-flashing-design.md)

- [x] Add model presentation fields and migration, expose them in inventory and owned-device responses, and add catalog editor controls. Verify existing model associations and feature resolution.
- [x] Implement account-scoped theme selection and model artwork in Flutter. Verify single/multiple theme behavior, missing metadata and readable audio routes.
- [x] Compile factory and legacy update images from archived credentials in isolated temporary directories. Restrict builds to supported model targets and protect NVS, LittleFS and ownership on updates.
- [x] Add admin-only package and reset routes with board-specific recovery, permission checks, and pending reset handling.
- [x] Add the Web Serial flow with probe, explicit action, integrity and write verification, reconnect and interruption recovery. Verify with mocked serial and check the physical v2 partition layout over COM7.
- [ ] Run suites and builds, review the diff, and push to GitHub.
- [ ] Validate a browser write and reset on a test board through a secure portal deployment.
