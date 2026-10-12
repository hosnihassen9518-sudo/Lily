from alembic import op
import sqlalchemy as sa
revision='20261012_widgets'
down_revision='20261011_lifecycle'
branch_labels=None
depends_on=None

def upgrade():
    existing=set(sa.inspect(op.get_bind()).get_table_names())
    if 'device_provisioning' not in existing:
        op.create_table('device_provisioning',sa.Column('device_id',sa.Integer(),sa.ForeignKey('devices.id',ondelete='CASCADE'),primary_key=True),sa.Column('encrypted_config',sa.Text(),nullable=False))
    if 'widget_credentials' not in existing:
        op.create_table('widget_credentials',sa.Column('token_hash',sa.String(64),primary_key=True),sa.Column('session_id',sa.String(64),sa.ForeignKey('mobile_sessions.id',ondelete='CASCADE'),nullable=False),sa.Column('installation_id',sa.String(32),nullable=False),sa.UniqueConstraint('session_id','installation_id',name='uq_widget_session_installation'))
        op.create_index('ix_widget_credentials_session_id','widget_credentials',['session_id'])

def downgrade():
    op.drop_table('widget_credentials');op.drop_table('device_provisioning')
