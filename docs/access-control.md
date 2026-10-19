# Lily 0.9 access control

## Roles and scope

Each account or API credential may have at most one assigned role. Unassigned permissions are denied. Predefined Superuser,
Administrator, Operator and Read-only definitions cannot be edited/deleted; custom portal
and API roles are editable. The portal matrix comes from GET /api/v1/access/permissions.
Only actions actually supported by a feature appear. Account removal uses disabling
(users.change); deleting a whole device/inventory record uses devices.delete. Device-type
catalog supports read/create; device-model changes have their own permissions.

Superuser includes every registered permission and explicit global resource scope. Only
superusers assign superuser status and set delegated grant ceilings. Other administrators
must hold the relevant create/change/assign permission AND a superuser-defined grant ceiling.
They cannot grant beyond their own rights or manage higher-privileged targets. The last
active superuser cannot be disabled/demoted. Operator and Read-only exclude account information and security settings.
API roles use a separate audience and explicit
api_roles.create/change/delete/assign permissions. Generic roles.create does not grant API-role
administration. API credentials require api_credentials.create and api_roles.assign.

Ordinary mobile users keep owned-resource access. Portal roles constrain mobile grants too.
API clients receive explicit device/home IDs or explicitly global scope. Ownership-delegated
access stops working if a resource leaves the issuer's ownership. Issuer revocation propagates through descendant API principals, and
child credential scopes cannot exceed their parent session's resource scope. Hardware capability checks,
device generations and signed lifecycle messages remain required in addition to RBAC.

## Sessions

Permissions are snapshotted on login/exchange. Each request checks token signature, session
activity/expiry, required permission and resource scope; role membership is not reconstructed
per request. Role changes, assignments, ceiling reductions, account disable and credential
revocation revoke affected sessions transactionally. Role changes take effect through fresh
login. Pairing tokens also depend on their active parent session; previously issued unbound
pairing tokens must be regenerated after this upgrade. A request already executing at the time of revocation may finish.

Portal sessions use ACCESS_TOKEN_EXPIRE_MINUTES (default 30). API sessions default to 15
minutes and cannot outlive their credential. API sessions have no refresh token. Mobile
refresh rotation stays intact and widgets depend on their parent mobile session. Session
management permits self-revocation; managing others needs sessions.read/revoke plus proper
delegation scope. Credential secrets and bearer tokens are never shown in session lists. Ordinary mobile
users have self-service session access only, without delegated session-management grants.

## API authentication example

1. In API roles, create a role such as devices.read and devices.control.
2. In API access, create a named, expiring credential and choose its resource IDs.
3. Save the secret once in your integration's secret store. Only its SHA-256 digest is stored. Inventory creation is separate from device-secret export;
a creator without inventory.export_secrets receives metadata without secrets or config headers.
4. Exchange over HTTPS:

```http
POST /api/v1/auth/api/exchange
Content-Type: application/json

{"credential":"<one-time API credential>"}
```

The response contains access_token, token_type, session_id and expires_at. Use
Authorization: Bearer <access_token> on requests such as GET /api/v1/devices or
PUT /api/v1/devices/42/light with {"enabled":true,"brightness":30,"r":0,"g":0,"b":255}.
The model must advertise those capabilities. Long-lived API credentials are accepted only
at the exchange endpoint. Expired/revoked credentials return 401; missing grants return 403;
out-of-scope resources return 404; throttling returns 429 with Retry-After seconds.
Never put credentials in URLs. The live OpenAPI schema declares x-lily-permission for routes.

## Limits

Limits use atomic database buckets shared across workers, with bounded expiry cleanup.
Defaults: login IP 10/min; failed account 5/15min; API exchange IP 30/min and known credential
10/min; session 120/min; API principal 120/min across sessions; sensitive writes/control
30/min per principal. Each credential also has an aggregate rate cap. Unknown credential
identifiers do not create their own buckets. Authenticated denied requests count too.
Rate limits can be managed in Settings. Delegated settings administrators can lower limits
within their grant ceiling; superusers may raise system ceilings. No permanent lockout is
introduced. Only explicitly trusted proxy peers may supply client-IP/HTTPS headers.

## Upgrade and recovery

Back up the database, root/backend environment files, signing key, provisioning archive and
music volume. Stop the backend during the migration; do not run mixed 0.8/0.9 workers.
Alembic adds access tables without changing device identities, pairing, keys or owners.
Existing admins become Administrator. Only the active admin matching ADMIN_EMAIL becomes
Superuser during the first upgrade. Later starts never re-promote or reactivate accounts.
If that admin cannot be found, startup fails with recovery instructions. With trusted local
server/database access, run from backend:

```powershell
$env:PYTHONPATH='.'
python -m app.services.rbac_recovery --email existing-active-user@example.com
```

This explicitly restores Superuser and records the recovery. Portal users must sign in again.
Old mobile sessions without a snapshot must sign in again once; devices need no re-pairing.
Do not downgrade a live migrated database without first restoring its matching 0.8 backup.

## HTTPS deployment

Set ENVIRONMENT=production, a strong random SECRET_KEY of at least 32 characters, secure
bootstrap credentials and exact production CORS_ORIGINS. Set TRUSTED_PROXY_IPS to a comma-
separated list of immediate proxy peer IPs, not arbitrary client addresses. Uvicorn must use
--no-proxy-headers so the application can validate those headers itself. Docker uses this
flag. See deploy/reverse-proxy/Caddyfile.example. For a host-native reverse proxy that reaches
host-native Uvicorn on loopback, the peer is typically 127.0.0.1; container networking may use
a bridge gateway instead. Verify the actual peer address before setting it. Build the portal
with VITE_API_BASE_URL=https://your-host/api/v1. Backend configuration does not override an
already-built portal's URL. API clients and mobile app backend settings must use HTTPS.

Legacy ESP32 activation/runtime traffic can remain LAN-only HTTP for compatibility; do not
publish device-runtime/activation endpoints or port 6100 on the internet. The sample Caddy
config denies those paths at the public proxy. Production HTTPS checks protect user/API auth
and authenticated traffic. TLS certificates, DNS, network firewall and proxy installation
remain deployment work; this branch does not change the live server.

## Auditing

The Audit view records privileged mutations, denied authenticated changes, secret exports,
credential issuance/revocation/exchange and recovery without request bodies or secrets.
Audit reads require audit.read; there is no application API to edit/delete events. Audit and
session lists are bounded to protect the portal from unbounded result sets.

### HTTP and HTTPS deployment

The basic Compose stack serves HTTP on portal port 6080 and backend port 6100. It defaults REQUIRE_HTTPS to false so authentication works on a trusted local network. HTTP does not encrypt credentials or tokens. For TLS deployments set REQUIRE_HTTPS=true in the root .env, configure the HTTPS reverse proxy and TRUSTED_PROXY_IPS, then recreate the backend. The backend setting itself defaults to true outside Compose.

### Administrator device management correction

Administrator has all operational device permissions, including provisioning, factory secret/config export and global device/home scope. Administrator does not receive account, role, API role, API credential or delegation management permissions. Superuser retains those additional controls. On startup, predefined role definitions are synchronized to the shipped definitions; changed definitions revoke affected sessions, requiring a fresh login.

Devices support PATCH /api/v1/devices/admin/{id}/model with model_key, guarded by devices.change and resource access. It accepts compatible firmware targets and hardware revisions, updates the model/type association, preserves credentials and ownership, and audits the change. It does not reflash firmware or rewrite the archived factory configuration. Fresh inventory accepts an optional name.

Role assignment and account/credential creation reject multiple roles. Existing conflicting assignments are preserved for superuser correction; their sessions are revoked on startup and new login is blocked until one role is selected. Removing the last active superuser remains prohibited.

Upgrade recovery: existing portal Superusers with extra roles retain only Superuser automatically, with an audit event and session revocation. This preserves their existing full authority. Other conflicting assignments require explicit correction. Offline recovery remains available via python -m app.services.rbac_recovery --email ACCOUNT_EMAIL.
