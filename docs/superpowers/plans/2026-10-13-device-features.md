# Device Features Implementation Plan

> Use superpowers:subagent-driven-development for independent implementation tasks.

**Goal:** Model-driven controls, separate configuration and faster widget feedback.
**Architecture:** Extend the existing model catalog and capability serializer;
app and admin consume explicit effective capabilities. Preserve native startup.
**Stack:** FastAPI/SQLAlchemy/Alembic, React/Vite, Flutter, Kotlin WorkManager.
**Spec:** ../specs/2026-10-13-device-features-design.md

## Constraints
Preserve cloud theme, model identities, ownership/generation enforcement,
secure sessions and release ProGuard constructor retention. Empty features deny.

## Tasks
- [x] Backend: write failing feature/model tests; implement model capabilities
  migration, admin CRUD/catalog and validation, effective serializer and command
  enforcement. Run applicable backend suite and migration checks.
- [x] Mobile: failing visibility/configuration tests; implement separate
  Configuration screen, Location wording, status dot and explicit capability
  helpers; omit unsupported light fields in API. Verify all Flutter tests.
- [x] Admin: tests for model edit/create/delete and validation; implement
  feature checkboxes/catalog and model management using agreed API; production build.
- [x] Widget: reproduce queue/feedback defects, separate refresh from commands,
  immediate pending feedback and consistent confirmed-state handling; verify native
  source and release behavior.
- [x] Review integrations, fix findings, run suites, bump APK version to 0.10.0+9
  and update CI artifact metadata. Build/cold-launch release on Pixel 10 Pro XL,
  inspect screen/crashes, generate APK, commit and push feature branch, then integrate into main following the user’s existing preference.

## Review focus
Empty/legacy capabilities, crafted API bypasses, metadata model reassignment,
model deletion in use, lost/stale widget commands, release reflection stripping,
offline controls, and narrow-screen/large-text configuration layout.
