# Execution ledger

Branch: codex/lily-0.9-rbac; base: 3065062.
Preflight: session, delegation, resource scope and route interfaces checked against approved spec.
Ruling: dedicated feature branch in existing checkout, as approved in plan; preserve generated/local files. Cost if wrong: local unrelated changes coexist but are excluded from staging.
Ruling: PowerShell/Python bookkeeping replaces POSIX skill helpers on Windows. Cost if wrong: manual ledger maintenance.
Task 1: role tests RED then GREEN; bootstrap uniqueness, additive migration, custom roles and concurrent last-superuser guard verified.
Task 2: snapshot/revocation tests RED then GREEN; immutable grants, legacy reauthentication, mobile/widget parent checks implemented.
Task 3: credential lifecycle RED then GREEN; delegated API permissions, one-time hashed secrets, role editing, issuer reduction and safe audit tested.
Task 4: route guards RED then GREEN; recursive included-router coverage verifies all authenticated dependencies. Resource-transfer regression RED then GREEN.
Task 5: rate tests RED then GREEN; exact boundaries, concurrent shared buckets, HTTPS spoofing and public registration throttling verified.
Task 6: portal tests RED then GREEN: 13 pass; production build passes. Browser verification in progress.
Ruling: Superuser receives explicit global scope; ordinary users retain ownership boundaries. Legacy schedule test now verifies both. Cost if wrong: deliberately broad privileged access.
Ruling: Tasks 1-5 committed as an integrated backend milestone because route, session and credential dependencies are shared. Cost if wrong: larger initial integration diff.
Task 7: in progress; release documentation, independent review and push pending.
