"""Add catalog presentation and board-bound factory provisioning."""
from alembic import op
import sqlalchemy as sa

revision = '20261113_catalog_usb'
down_revision = '20261103_private_music'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column['name'] for column in inspector.get_columns('device_models')}
    for name, size in [('theme_key', 32), ('image_key', 64)]:
        if name not in columns:
            op.add_column('device_models', sa.Column(name, sa.String(size), nullable=True))
    if 'usb_provisioning' not in inspector.get_table_names():
        op.create_table(
            'usb_provisioning',
            sa.Column('mac', sa.String(12), primary_key=True),
            sa.Column('device_id', sa.Integer(), sa.ForeignKey('devices.id', ondelete='CASCADE'), unique=True, nullable=False),
            sa.Column('pending_package', sa.LargeBinary(), nullable=True),
            sa.Column('pending_mode', sa.String(8), nullable=True),
            sa.Column('completed_token_hash', sa.String(64), nullable=True),
        )
    for key, old_name, name, image in (
        ('lily_led_strip', 'Lily LED Strip', 'Lily Light', 'lily-light'),
        ('lily_v2', 'Lily V2', 'Lily Light + Speaker', 'lily-speaker'),
    ):
        bind.execute(sa.text('''
            UPDATE device_models
            SET name = CASE WHEN name = :old_name THEN :name ELSE name END,
                theme_key = 'kids', image_key = :image
            WHERE key = :key
        '''), dict(key=key, old_name=old_name, name=name, image=image))
        bind.execute(sa.text('''
            UPDATE devices SET model = :name WHERE model = :old_name
              AND EXISTS (SELECT 1 FROM device_models WHERE key = :key AND name = :name)
        '''), dict(key=key, old_name=old_name, name=name))


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM usb_provisioning')).scalar():
        raise RuntimeError('USB provisioning identities must be retained before downgrading')
    op.drop_table('usb_provisioning')
    op.drop_column('device_models', 'image_key')
    op.drop_column('device_models', 'theme_key')
