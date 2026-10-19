from app.models.access_control import AuditEvent


def audit(db, actor_id, action, target, result="success"):
    # Deliberately no arbitrary request payloads; only identifiers and action names.
    db.add(
        AuditEvent(
            actor_id=actor_id,
            action=action,
            target=str(target)[:160],
            result=result,
            details={},
        )
    )
