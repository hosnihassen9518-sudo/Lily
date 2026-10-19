# Lily v0.9.0: RBAC, revocable sessions, and managed API access

Date: 2026-10-19
Status: Written specification approved; implemented in v0.9.0, live deployment pending.
Repository: D:/Projects/Lily/Lily

## Outcome and scope

Add feature-level roles and permissions to the existing FastAPI backend and React admin portal. Resolve permissions when a session starts, allow authorized admins to revoke sessions, enforce rate limits, and provide portal-managed API credentials and roles. Preserve device identities, mobile pairing, account ownership, and the LED strip work already present locally. Prepare and test locally; production deployment and live integration testing follow when the user supplies administrator access.

## Authorization model

Use an explicit permission catalog with resource/action identifiers. Resources cover dashboard, users, devices, device inventory, device models, device types, homes/rooms, music, schedules, settings, roles, API roles, API credentials, sessions, and audit logs. Supported actions are read, create, change, delete, control, export, export_secrets, and assign, only where meaningful. Separate credential exports from ordinary reads. Separate device control from editing device metadata. Permissions not explicitly granted are denied. New endpoints must declare an authorization policy; no authenticated administrative endpoint may rely on the old is_admin flag alone.

Assignments can include multiple roles; their grants combine by union. There are no explicit deny overrides in this release. Role names and descriptions are editable for custom roles. A role has a portal-user or API-client audience; API roles cannot confer interactive portal access. API administration is delegated using separate api_roles.create/change/delete/assign and api_credentials.create/read/revoke permissions. Generic role-edit permission does not implicitly permit API-role administration.

Fixed predefined roles:

- Superuser: all registered permissions, including future additions. Only superusers grant/revoke superuser status and manage the grant ceilings of delegated administrators.
- Administrator: all ordinary operational administration, excluding role/assignment changes, API access administration, session revocation for other users, and secret exports unless separately delegated.
- Operator: operational reads plus device control and schedule management, excluding accounts, security settings, credentials, and factory secrets.
- Read-only: operational views; no writes, device control, secret exports, or credential access.

Predefined role definitions cannot be changed or deleted. Their assignments can be managed subject to permission checks. Custom roles can be changed or deleted; an assigned role must be unassigned before deletion. Prevent self-escalation: role grants, role assignment, API issuance, and later role edits must remain within the actor's effective permission set and superuser-defined grant ceiling. Delegated administrators cannot alter protected users or credentials belonging to higher-privileged principals. Protect the last active superuser against disabling, demotion, or deletion, including concurrent attempts.

## Sessions and permission snapshots

At interactive login, create a server-side session with principal, immutable effective permission snapshot, creation time, expiry, revocation state, and authentication method. Tokens reference the session; do not reconstruct role grants from the database on every request. Each protected request still validates token authenticity, session existence/expiry/revocation, and the required action against its snapshot. Cache-free session lookup in this release gives revocation effect on the next request, including across workers.

Role changes, assignments, grant-ceiling reductions, and account disabling revoke affected sessions transactionally. Clients reauthenticate to obtain updated grants. Expired or revoked sessions cannot refresh. Session renewal never preserves withdrawn privileges. Existing mobile refresh sessions keep their rotation and replay protection; integrate them with revocation and restrict them to owned resources. Widget sessions must also respect parent-session revocation. Device-runtime identity/signature routes retain their separate authentication and are not accepted as human sessions.

Portal session management displays principal, session identifier prefix, creation, expiry, authentication type, and last activity. Users can revoke their own sessions. An admin needs sessions.read/revoke and appropriate delegation scope to inspect/revoke others. Support revoke one and revoke all; full tokens and credentials are never displayed.

## API credentials and API sessions

Authorized portal users create named API credentials for a service principal, assign API roles, set credential expiry, and configure a rate-limit policy. Generate at least 256 random bits; show the secret once and persist only a cryptographic digest plus a public lookup identifier. List metadata, expiry, revocation, and last use without exposing secrets.

Exchange an API credential at a dedicated authentication endpoint for a short-lived bearer session (default 15 minutes, without a refresh token). Do not allow long-lived credentials on ordinary resource endpoints. Snapshot permissions are the intersection of assigned API roles and the issuer's current allowed permissions/grant ceiling at issuance. Issuer disabling or loss of delegated grants, API-role edits, and credential revocation invalidate affected API sessions and prevent reissuance beyond the current ceiling. No API principal receives the Superuser role. API role/credential administration requires the corresponding explicit permissions; authentication method alone confers no authority.

Use HTTPS for production credential exchange and portal/API traffic, via a documented reverse proxy with explicitly trusted forwarding configuration. Local development can use loopback HTTP. Do not expose the existing device transport to the internet as a consequence of this change. Keep existing LAN device activation compatibility; document that device transport hardening is separate work. No credentials in URLs, audit payloads, exception messages, or logs.

## Resource boundaries

A global permission does not by itself bypass ownership. Mobile users continue to access their own devices, homes, rooms, and schedules. API service principals have explicit resource scope: specified devices/homes or all resources if an appropriately authorized administrator grants that scope. Evaluate object scope on each request alongside the permission snapshot. Keep lifecycle generation checks and model capability checks for controls. Role authorization and hardware capability authorization must both pass.

## Rate limiting

Use shared database-backed atomic rate buckets initially, compatible with SQLite locally and PostgreSQL deployments. Do not rely on per-process memory for production limits. Bound and periodically clean expired buckets. Return HTTP 429 and Retry-After, and document reset semantics.

Defaults: interactive login 10 attempts per IP per minute plus 5 failed attempts per normalized account per 15 minutes; API exchange 10 per credential identifier per minute plus 30 per IP per minute; authenticated sessions 120 requests per minute; API client aggregate 120 per minute across all sessions plus the session limit; sensitive writes/control 30 per minute per principal. These are initial configurable defaults, not permanent lockouts. Hash account bucket identifiers; do not leak account existence. Unauthorized random credential IDs must not allow unbounded storage growth. Trust forwarded client addresses only from configured proxies. Rate-limit policy edits require explicit settings.change permission and a delegation ceiling; superusers retain full policy control.

## Persistence, migrations, and bootstrap

Add roles, role permissions, principal-role assignments, delegation ceilings, API principals/credentials, authentication sessions, resource scopes, audit events, and rate buckets with indexed foreign keys and expiries. Store role revision in session metadata for diagnostics. Use an Alembic migration and idempotent role seeding that never overwrites custom roles or edited assignments. Predefined role IDs/keys are stable.

Upgrade existing active administrators to Administrator. Promote the configured bootstrap administrator to Superuser only once during migration/bootstrap, with an explicit recovery command if it cannot be uniquely identified; never silently grant all existing admins Superuser. Ordinary users retain owned-resource mobile access. Legacy portal JWTs without revocable session IDs must reauthenticate. Preserve mobile session data while adding the new checks; a migration may require one fresh mobile login but must not require re-pairing devices. Startup must not recreate or re-promote disabled users on every restart.

## Portal and API surface

Add Users/Administrators, Roles, API Roles, API Access, Sessions, and Audit views to the existing layout. Permission matrices show one row per feature and action columns. Predefined roles display locked definitions. Hide inaccessible navigation, disable unavailable actions, and handle backend denials without exposing hidden data. The server remains authoritative. On expired/revoked sessions, clear authentication and prompt for login. Expose the current session's effective permissions through /auth/me for portal rendering.

Publish OpenAPI documentation and examples for credential exchange, device reads/controls, permission errors, expiry, revocation, and rate limiting. Audit privileged mutations and API credential creation/revocation with actor, target, timestamp, result, and safe metadata; never log passwords, keys, bearer tokens, or device secrets. Audit reads need their own permission; audit events are append-only through application APIs.

## Validation and release

Test permission allow/deny matrices across every protected route, ownership boundaries, custom/predefined role rules, delegation ceilings, attempted escalation, last-superuser races, snapshot creation, role-change invalidation, mobile/widget revocation, API expiry/revocation, one-time credential disclosure, issuer privilege reduction, shared rate limits, and migration idempotence/data preservation. Include portal tests for role editing, permitted navigation/actions, sessions, API issuance, and error states. Build the portal and run backend and mobile regression suites. Report existing Windows-only test limitations separately.

Version backend and portal as 0.9.0. Deliver release notes, migration/backup/recovery instructions, permission catalog, API examples, deployment configuration, and verification evidence. Do not publish, change live administrator assignments, or migrate the running server until live access is available and the prepared release is reviewable.

Security reference: https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html
