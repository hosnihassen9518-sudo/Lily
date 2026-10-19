"""Atomic fixed-window buckets shared by every backend worker."""

import hashlib, time, ipaddress
from fastapi import HTTPException
from sqlalchemy import case, select, delete
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.models.access_control import RateBucket, ApiCredential
from app.models.device_lifecycle import AppSetting
from app.core.config import settings

DEFAULTS = {
    "login_ip": 10,
    "login_account": 5,
    "exchange_ip": 30,
    "exchange_credential": 10,
    "session": 120,
    "api_principal": 120,
    "sensitive": 30,
    "light_controls": 300,
}


def policies(db):
    row = db.get(AppSetting, "access_rate_limits")
    return {**DEFAULTS, **(row.value_json if row else {})}


def consume_limit(db, bucket, limit, window_seconds, now=None):
    now = int(time.time() if now is None else now)
    key = hashlib.sha256(bucket.encode()).hexdigest()
    table = RateBucket.__table__
    insert = pg_insert if db.bind.dialect.name == "postgresql" else sqlite_insert
    statement = insert(table).values(key=key, count=1, reset_at=now + window_seconds)
    statement = statement.on_conflict_do_update(
        index_elements=[table.c.key],
        set_={
            "count": case((table.c.reset_at <= now, 1), else_=table.c.count + 1),
            "reset_at": case(
                (table.c.reset_at <= now, now + window_seconds), else_=table.c.reset_at
            ),
        },
    )
    db.execute(statement)
    row = db.execute(
        select(table.c.count, table.c.reset_at).where(table.c.key == key)
    ).one()
    db.execute(delete(RateBucket).where(RateBucket.reset_at < now - 3600))
    db.commit()
    if row.count > limit:
        raise HTTPException(
            429,
            "Rate limit exceeded",
            headers={"Retry-After": str(max(1, row.reset_at - now))},
        )


def check_failed_account(db, email):
    key = hashlib.sha256(("failed:" + email.strip().lower()).encode()).hexdigest()
    row = db.get(RateBucket, key)
    if (
        row
        and row.reset_at > int(time.time())
        and row.count >= policies(db)["login_account"]
    ):
        raise HTTPException(
            429,
            "Sign-in temporarily rate limited",
            headers={"Retry-After": str(max(1, row.reset_at - int(time.time())))},
        )


def failed_account(db, email):
    consume_limit(
        db, "failed:" + email.strip().lower(), policies(db)["login_account"], 900
    )


def client_ip(request):
    host = request.client.host if request.client else "unknown"
    trusted = [x.strip() for x in settings.trusted_proxy_ips.split(",") if x.strip()]
    if host in trusted:
        candidate = request.headers.get("x-forwarded-for", "").split(",")[-1].strip()
        try:
            return str(ipaddress.ip_address(candidate))
        except ValueError:
            pass
    return host


def require_https(request):
    if settings.environment != "production" or not settings.require_https:
        return
    secure = request.url.scheme == "https"
    host = request.client.host if request.client else ""
    if (
        host in settings.trusted_proxy_ips.split(",")
        and request.headers.get("x-forwarded-proto") == "https"
    ):
        secure = True
    if not secure:
        raise HTTPException(400, "HTTPS is required")


def login_limit(db, request, email):
    require_https(request)
    consume_limit(db, "login-ip:" + client_ip(request), policies(db)["login_ip"], 60)
    # The IP window bounds account bucket creation even for unknown email addresses.
    check_failed_account(db, email)


def session_limit(db, request, context):
    require_https(request)
    values = policies(db)
    endpoint = request.scope.get("endpoint")
    smooth_light = (
        context.auth_method == "mobile"
        and request.method == "PUT"
        and getattr(endpoint, "__module__", "") == "app.api.devices"
        and getattr(endpoint, "__name__", "") == "set_light"
    )
    if smooth_light:
        consume_limit(db, "light-session:" + context.session_id, values["light_controls"], 60)
        consume_limit(db, "light-user:" + str(context.principal.id), values["light_controls"], 60)
        consume_limit(db, "light-burst:" + str(context.principal.id), 10, 1)
    else:
        consume_limit(db, "session:" + context.session_id, values["session"], 60)
    if context.auth_method == "api":
        consume_limit(
            db, "api:" + str(context.principal.id), values["api_principal"], 60
        )
        from app.models.access_control import AccessSession

        session = db.get(AccessSession, context.session_id)
        credential = db.get(ApiCredential, session.credential_id)
        if credential:
            consume_limit(
                db,
                "credential:" + credential.id,
                min(values["api_principal"], credential.rate_limit),
                60,
            )
    if not smooth_light and request.method not in ("GET", "HEAD", "OPTIONS"):
        consume_limit(
            db, "sensitive:" + str(context.principal.id), values["sensitive"], 60
        )
    from app.models.access_control import AccessSession
    from sqlalchemy import update
    from datetime import datetime, timezone, timedelta

    now = datetime.now(timezone.utc)
    db.execute(
        update(AccessSession)
        .where(
            AccessSession.id == context.session_id,
            AccessSession.last_activity < now - timedelta(minutes=1),
        )
        .values(last_activity=now)
    )
    db.commit()


def public_auth_limit(db, request):
    require_https(request)
    consume_limit(db, "login-ip:" + client_ip(request), policies(db)["login_ip"], 60)
