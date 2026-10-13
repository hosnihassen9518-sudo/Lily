from alembic import op
import sqlalchemy as sa

revision = '20261013_model_features'
down_revision = '20261012_widgets'
branch_labels = None
depends_on = None

def upgrade():
    connection = op.get_bind()
    if 'capabilities' not in {c['name'] for c in sa.inspect(connection).get_columns('device_models')}:
        op.add_column('device_models', sa.Column('capabilities', sa.JSON(none_as_null=True), nullable=True))
    metadata = sa.MetaData()
    models = sa.Table('device_models', metadata, autoload_with=connection)
    devices = sa.Table('devices', metadata, autoload_with=connection)
    profiles = sa.Table('device_profiles', metadata, autoload_with=connection)
    catalog = list(connection.execute(sa.select(models)).mappings())
    for device in connection.execute(sa.select(devices)).mappings():
        matches = [m for m in catalog if device['model'] in (m['key'], m['name'])]
        if len(matches) != 1: continue
        model = matches[0]
        profile = connection.execute(sa.select(profiles).where(profiles.c.device_id == device['id'])).mappings().first()
        if profile:
            values = dict(profile['metadata_json'] or {})
            if values.get('model_key'): continue
            values['model_key'] = model['key']
            connection.execute(profiles.update().where(profiles.c.device_id == device['id']).values(
                metadata_json=values, device_type_id=model['device_type_id']))
        else:
            connection.execute(profiles.insert().values(device_id=device['id'], device_type_id=model['device_type_id'],
                                                        metadata_json={'model_key':model['key']}, updated_at=sa.func.now()))

def downgrade():
    op.drop_column('device_models', 'capabilities')
