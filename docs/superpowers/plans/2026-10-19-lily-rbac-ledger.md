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

Final independent review: gpt-6-astra reviewed 3065062..27cdbbe read-only; eight actionable findings, all addressed.
Final: fixed ordinary-mobile cross-user session access; default mobile grants no longer include delegated session management; test_mobile_users_cannot_manage_each_others_sessions passes.
Final: fixed legacy admin route ownership checks, creation-time secret redaction, unmatched bootstrap account creation, legacy-admin recovery, parent-bound pairing revocation, and predefined role exclusions. Targeted reproductions failed before fixes and pass after.
Final: fixed audit dependency-close lifecycle after real HTTP 500 reproduction; test_audit_survives_real_dependency_session_cleanup RED then GREEN; live denied writes now return 403.
Final: fixed transitive API revocation and parent-scope widening; descendant and scope tests RED then GREEN.
Final: regraded the models-only page finding from Minor to Important because an authorized feature could not load; optional catalogue request test RED then GREEN. Fixed the browser-found read-only create button through its RED/GREEN regression.
Ruling: classify authorized models-page loading failure as functional, rather than deferred polish. Cost if wrong: an additional conditional catalogue fetch; models-only users see numeric type IDs when type reads are unavailable.
Ruling: make the two pre-existing host-specific tests portable: explicitly skip missing g++, and keep key recovery assertions while testing POSIX bits only on POSIX. Cost if wrong: host C++ compilation and Windows ACLs remain unverified locally.
Verification: unfiltered backend 87 passed, 2 skipped (host g++ unavailable; PostgreSQL test environment unavailable); portal 14 passed and production build succeeds; Flutter 67 passed; both LED-strip and ordinary test-light builds succeed.
Live preview: fresh isolated database; admin login, API role/key creation, exchange, credential aggregate 429, revocation 401, read-only denial 403, administrator revocation all pass. Browser confirms read-only navigation and disabled actions. No production data accessed.
Deferred minors: none. PostgreSQL concurrency and deployment proxy/TLS have not been exercised against the user's live server.
Task 7: verification and release documentation complete; GitHub push pending.
