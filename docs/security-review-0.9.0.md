# Lily 0.9.0 security review and verification

Independent review covered commits 3065062..27cdbbe. The final fix pass addressed:

- Cross-user mobile session management: self-service access is separate from delegated grants.
- Legacy administrative routes: ownership/global scope also applies to lists, mutations, exports, secrets and resync.
- Upgrade mapping: existing installations never silently create a replacement superuser.
- Inventory creation: secret/config fields require independent export permission.
- Recovery: other legacy administrators retain ordinary Administrator roles.
- Pairing: tokens require an active originating session and retained pairing permission.
- Fixed Operator/Read-only roles: account information and security settings excluded.
- Models-only portal access: optional device-type reads no longer block authorized models.

Live HTTP testing additionally caught expired/detached ORM state in audit middleware; it now
captures primitive actor state and writes through an independent journal session. API issuer
revocation follows descendant principals, and child credentials cannot broaden parent scopes.
The browser-found read-only create-button state also has a regression test.

Verification: backend 87 passed / 2 explicit environment skips, portal 14 passed plus build,
Flutter 67 passed, both test-light firmware environments build. A fresh loopback-only server
passed API issuance/exchange/rate-limit/revocation/read-only/session checks. No live deployment
was performed. Host C++ compilation and PostgreSQL concurrency need their respective tools;
production TLS/proxy configuration must be validated during deployment.

Implementation rulings, evidence and test names are in the execution ledger. There are no
deferred review findings. The independent reviewer did not re-review the fix pass; fixes were
verified by reproducing tests and the final suites.
