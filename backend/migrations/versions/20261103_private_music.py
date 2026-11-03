"""Owner-scoped uploaded tracks; existing tracks remain shared."""
from alembic import op
import sqlalchemy as sa

revision = '20261103_private_music'
down_revision = '20261019_rbac'
branch_labels = None
depends_on = None


def upgrade():
    conn = op.get_bind()
    if 'owner_id' not in {c['name'] for c in sa.inspect(conn).get_columns('music')}:
        with op.batch_alter_table('music') as batch:
            batch.add_column(sa.Column('owner_id', sa.Integer(), nullable=True))
            batch.create_foreign_key('fk_music_owner_id', 'users', ['owner_id'], ['id'], ondelete='CASCADE')
            batch.create_index('ix_music_owner_id', ['owner_id'])


def downgrade():
    # Dropping ownership would turn private files into shared catalog entries.
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM music WHERE owner_id IS NOT NULL')).scalar():
        raise RuntimeError('Remove private tracks before downgrading their ownership schema')
    with op.batch_alter_table('music') as batch:
        batch.drop_index('ix_music_owner_id')
        batch.drop_column('owner_id')
