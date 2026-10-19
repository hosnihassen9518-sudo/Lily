"""Add RBAC persistence; frozen schema, no account/device identity changes."""

from alembic import op
import sqlalchemy as sa

revision = "20261019_rbac"
down_revision = "20261013_model_features"
branch_labels = None
depends_on = None


def schema():
    metadata = sa.MetaData()
    sa.Table("users", metadata, sa.Column("id", sa.Integer, primary_key=True))
    sa.Table(
        "access_roles",
        metadata,
        sa.Column("key", sa.String(80), primary_key=True, nullable=False, index=False),
        sa.Column(
            "name", sa.String(120), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "audience", sa.String(16), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "predefined", sa.Boolean(), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "permissions", sa.JSON(), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "revision", sa.Integer(), primary_key=False, nullable=False, index=False
        ),
    )
    sa.Table(
        "access_role_assignments",
        metadata,
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id"),
            primary_key=True,
            nullable=False,
            index=False,
        ),
        sa.Column(
            "role_key",
            sa.String(80),
            sa.ForeignKey("access_roles.key"),
            primary_key=True,
            nullable=False,
            index=False,
        ),
    )
    sa.Table(
        "access_grant_ceilings",
        metadata,
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id"),
            primary_key=True,
            nullable=False,
            index=False,
        ),
        sa.Column(
            "permissions", sa.JSON(), primary_key=False, nullable=False, index=False
        ),
    )
    sa.Table(
        "access_service_principals",
        metadata,
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id"),
            primary_key=True,
            nullable=False,
            index=False,
        ),
        sa.Column(
            "issuer_id",
            sa.Integer(),
            sa.ForeignKey("users.id"),
            primary_key=False,
            nullable=False,
            index=True,
        ),
        sa.Column(
            "name", sa.String(120), primary_key=False, nullable=False, index=False
        ),
        sa.Column("scope", sa.JSON(), primary_key=False, nullable=False, index=False),
    )
    sa.Table(
        "access_api_credentials",
        metadata,
        sa.Column("id", sa.String(32), primary_key=True, nullable=False, index=False),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("access_service_principals.user_id"),
            primary_key=False,
            nullable=False,
            index=True,
        ),
        sa.Column(
            "name", sa.String(120), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "secret_hash", sa.String(64), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=False,
        ),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=True,
        ),
        sa.Column(
            "revoked_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=True,
            index=False,
        ),
        sa.Column(
            "last_used_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=True,
            index=False,
        ),
        sa.Column(
            "rate_limit", sa.Integer(), primary_key=False, nullable=False, index=False
        ),
    )
    sa.Table(
        "access_sessions",
        metadata,
        sa.Column("id", sa.String(64), primary_key=True, nullable=False, index=False),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id"),
            primary_key=False,
            nullable=False,
            index=True,
        ),
        sa.Column(
            "permissions", sa.JSON(), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "role_revisions", sa.JSON(), primary_key=False, nullable=False, index=False
        ),
        sa.Column("scope", sa.JSON(), primary_key=False, nullable=False, index=False),
        sa.Column(
            "auth_method", sa.String(16), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "credential_id",
            sa.String(32),
            sa.ForeignKey("access_api_credentials.id"),
            primary_key=False,
            nullable=True,
            index=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=False,
        ),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=True,
        ),
        sa.Column(
            "revoked_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=True,
            index=True,
        ),
        sa.Column(
            "last_activity",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=False,
        ),
    )
    sa.Table(
        "access_audit",
        metadata,
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False, index=False),
        sa.Column(
            "actor_id", sa.Integer(), primary_key=False, nullable=True, index=True
        ),
        sa.Column(
            "action", sa.String(120), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "target", sa.String(160), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "result", sa.String(16), primary_key=False, nullable=False, index=False
        ),
        sa.Column("details", sa.JSON(), primary_key=False, nullable=False, index=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            primary_key=False,
            nullable=False,
            index=True,
        ),
    )
    sa.Table(
        "access_rate_buckets",
        metadata,
        sa.Column("key", sa.String(160), primary_key=True, nullable=False, index=False),
        sa.Column(
            "count", sa.Integer(), primary_key=False, nullable=False, index=False
        ),
        sa.Column(
            "reset_at", sa.Integer(), primary_key=False, nullable=False, index=True
        ),
    )
    return metadata


TABLES = [
    "access_roles",
    "access_role_assignments",
    "access_grant_ceilings",
    "access_service_principals",
    "access_api_credentials",
    "access_sessions",
    "access_audit",
    "access_rate_buckets",
]


def upgrade():
    metadata = schema()
    for name in TABLES:
        metadata.tables[name].create(op.get_bind(), checkfirst=True)


def downgrade():
    metadata = schema()
    for name in reversed(TABLES):
        metadata.tables[name].drop(op.get_bind(), checkfirst=True)
