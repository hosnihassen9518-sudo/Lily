"""Freeze the initial schema and add missing tables on legacy installations."""
from alembic import op
import sqlalchemy as sa
revision = '20261011_lifecycle'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    existing = set(sa.inspect(op.get_bind()).get_table_names())
    if 'app_settings' not in existing:
        op.create_table('app_settings', sa.Column('key', sa.String(length=80), nullable=False), sa.Column('value_json', sa.JSON(), nullable=False), sa.PrimaryKeyConstraint('key'))
    if 'device_types' not in existing:
        op.create_table('device_types', sa.Column('id', sa.Integer(), nullable=False), sa.Column('key', sa.String(length=80), nullable=False), sa.Column('name', sa.String(length=120), nullable=False), sa.Column('description', sa.Text(), nullable=True), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.PrimaryKeyConstraint('id'))
    if 'device_types' not in existing:
        op.create_index(op.f('ix_device_types_key'), 'device_types', ['key'], unique=True)
    if 'music' not in existing:
        op.create_table('music', sa.Column('id', sa.Integer(), nullable=False), sa.Column('title', sa.String(length=200), nullable=False), sa.Column('description', sa.String(length=1000), nullable=True), sa.Column('filename', sa.String(length=255), nullable=False), sa.Column('storage_path', sa.String(length=500), nullable=False), sa.Column('filesize', sa.Integer(), nullable=False), sa.Column('checksum_sha256', sa.String(length=64), nullable=False), sa.Column('enabled', sa.Boolean(), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.PrimaryKeyConstraint('id'), sa.UniqueConstraint('storage_path'))
    if 'users' not in existing:
        op.create_table('users', sa.Column('id', sa.Integer(), nullable=False), sa.Column('email', sa.String(length=320), nullable=False), sa.Column('password_hash', sa.String(length=255), nullable=False), sa.Column('first_name', sa.String(length=100), nullable=True), sa.Column('last_name', sa.String(length=100), nullable=True), sa.Column('is_active', sa.Boolean(), nullable=False), sa.Column('is_admin', sa.Boolean(), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.PrimaryKeyConstraint('id'))
    if 'users' not in existing:
        op.create_index(op.f('ix_users_email'), 'users', ['email'], unique=True)
    if 'device_models' not in existing:
        op.create_table('device_models', sa.Column('key', sa.String(length=80), nullable=False), sa.Column('name', sa.String(length=120), nullable=False), sa.Column('device_type_id', sa.Integer(), nullable=False), sa.Column('hardware_version', sa.String(length=50), nullable=False), sa.Column('firmware_target', sa.String(length=80), nullable=False), sa.ForeignKeyConstraint(['device_type_id'], ['device_types.id']), sa.PrimaryKeyConstraint('key'))
    if 'device_type_capabilities' not in existing:
        op.create_table('device_type_capabilities', sa.Column('id', sa.Integer(), nullable=False), sa.Column('device_type_id', sa.Integer(), nullable=False), sa.Column('capability', sa.String(length=80), nullable=False), sa.Column('config', sa.JSON(), nullable=False), sa.ForeignKeyConstraint(['device_type_id'], ['device_types.id'], ondelete='CASCADE'), sa.PrimaryKeyConstraint('id'), sa.UniqueConstraint('device_type_id', 'capability', name='uq_type_capability'))
    if 'device_type_capabilities' not in existing:
        op.create_index(op.f('ix_device_type_capabilities_capability'), 'device_type_capabilities', ['capability'], unique=False)
    if 'device_type_capabilities' not in existing:
        op.create_index(op.f('ix_device_type_capabilities_device_type_id'), 'device_type_capabilities', ['device_type_id'], unique=False)
    if 'devices' not in existing:
        op.create_table('devices', sa.Column('id', sa.Integer(), nullable=False), sa.Column('serial_number', sa.String(length=80), nullable=False), sa.Column('secret_hash', sa.String(length=255), nullable=False), sa.Column('name', sa.String(length=120), nullable=True), sa.Column('model', sa.String(length=80), nullable=False), sa.Column('hardware_version', sa.String(length=50), nullable=True), sa.Column('firmware_version', sa.String(length=50), nullable=True), sa.Column('lifecycle_status', sa.String(length=30), nullable=False), sa.Column('owner_id', sa.Integer(), nullable=True), sa.Column('is_online', sa.Boolean(), nullable=False), sa.Column('last_seen', sa.DateTime(timezone=True), nullable=True), sa.Column('last_connected_at', sa.DateTime(timezone=True), nullable=True), sa.Column('last_disconnected_at', sa.DateTime(timezone=True), nullable=True), sa.Column('wifi_rssi', sa.Integer(), nullable=True), sa.Column('free_heap', sa.Integer(), nullable=True), sa.Column('free_storage', sa.Integer(), nullable=True), sa.Column('light_on', sa.Boolean(), nullable=False), sa.Column('brightness', sa.Integer(), nullable=False), sa.Column('color_r', sa.Integer(), nullable=False), sa.Column('color_g', sa.Integer(), nullable=False), sa.Column('color_b', sa.Integer(), nullable=False), sa.Column('audio_loaded', sa.Boolean(), nullable=False), sa.Column('audio_playing', sa.Boolean(), nullable=False), sa.Column('volume', sa.Integer(), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.Column('activated_at', sa.DateTime(timezone=True), nullable=True), sa.ForeignKeyConstraint(['owner_id'], ['users.id']), sa.PrimaryKeyConstraint('id'))
    if 'devices' not in existing:
        op.create_index(op.f('ix_devices_serial_number'), 'devices', ['serial_number'], unique=True)
    if 'homes' not in existing:
        op.create_table('homes', sa.Column('id', sa.Integer(), nullable=False), sa.Column('owner_id', sa.Integer(), nullable=False), sa.Column('name', sa.String(length=120), nullable=False), sa.Column('timezone', sa.String(length=80), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['owner_id'], ['users.id']), sa.PrimaryKeyConstraint('id'))
    if 'homes' not in existing:
        op.create_index(op.f('ix_homes_owner_id'), 'homes', ['owner_id'], unique=False)
    if 'mobile_sessions' not in existing:
        op.create_table('mobile_sessions', sa.Column('id', sa.String(length=64), nullable=False), sa.Column('user_id', sa.Integer(), nullable=False), sa.Column('current_refresh_hash', sa.String(length=64), nullable=False), sa.Column('previous_refresh_hash', sa.String(length=64), nullable=True), sa.Column('rotation_request_id', sa.String(length=64), nullable=True), sa.Column('rotated_at', sa.DateTime(timezone=True), nullable=True), sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False), sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True), sa.ForeignKeyConstraint(['user_id'], ['users.id']), sa.PrimaryKeyConstraint('id'), sa.UniqueConstraint('current_refresh_hash'))
    if 'mobile_sessions' not in existing:
        op.create_index(op.f('ix_mobile_sessions_user_id'), 'mobile_sessions', ['user_id'], unique=False)
    if 'device_identities' not in existing:
        op.create_table('device_identities', sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('receipt_public_key', sa.Text(), nullable=True), sa.Column('generation', sa.Integer(), nullable=False), sa.Column('protocol_version', sa.Integer(), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id']), sa.PrimaryKeyConstraint('device_id'))
    if 'device_operations' not in existing:
        op.create_table('device_operations', sa.Column('id', sa.String(length=64), nullable=False), sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('requested_by_id', sa.Integer(), nullable=False), sa.Column('generation', sa.Integer(), nullable=False), sa.Column('kind', sa.String(length=30), nullable=False), sa.Column('status', sa.String(length=30), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True), sa.Column('broker_cleanup_pending', sa.Integer(), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id']), sa.ForeignKeyConstraint(['requested_by_id'], ['users.id']), sa.PrimaryKeyConstraint('id'))
    if 'device_operations' not in existing:
        op.create_index(op.f('ix_device_operations_device_id'), 'device_operations', ['device_id'], unique=False)
    if 'device_states' not in existing:
        op.create_table('device_states', sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('state', sa.JSON(), nullable=False), sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'), sa.PrimaryKeyConstraint('device_id'))
    if 'device_states' not in existing:
        op.create_index(op.f('ix_device_states_updated_at'), 'device_states', ['updated_at'], unique=False)
    if 'device_telemetry' not in existing:
        op.create_table('device_telemetry', sa.Column('id', sa.Integer(), nullable=False), sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('metric', sa.String(length=100), nullable=False), sa.Column('numeric_value', sa.Float(), nullable=True), sa.Column('text_value', sa.Text(), nullable=True), sa.Column('extra', sa.JSON(), nullable=False), sa.Column('recorded_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'), sa.PrimaryKeyConstraint('id'))
    if 'device_telemetry' not in existing:
        op.create_index(op.f('ix_device_telemetry_device_id'), 'device_telemetry', ['device_id'], unique=False)
    if 'device_telemetry' not in existing:
        op.create_index(op.f('ix_device_telemetry_metric'), 'device_telemetry', ['metric'], unique=False)
    if 'device_telemetry' not in existing:
        op.create_index(op.f('ix_device_telemetry_recorded_at'), 'device_telemetry', ['recorded_at'], unique=False)
    if 'rooms' not in existing:
        op.create_table('rooms', sa.Column('id', sa.Integer(), nullable=False), sa.Column('home_id', sa.Integer(), nullable=False), sa.Column('name', sa.String(length=120), nullable=False), sa.Column('icon', sa.String(length=80), nullable=True), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['home_id'], ['homes.id'], ondelete='CASCADE'), sa.PrimaryKeyConstraint('id'), sa.UniqueConstraint('home_id', 'name', name='uq_room_home_name'))
    if 'rooms' not in existing:
        op.create_index(op.f('ix_rooms_home_id'), 'rooms', ['home_id'], unique=False)
    if 'schedules' not in existing:
        op.create_table('schedules', sa.Column('id', sa.Integer(), nullable=False), sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('user_id', sa.Integer(), nullable=False), sa.Column('name', sa.String(length=120), nullable=False), sa.Column('time_of_day', sa.Time(), nullable=False), sa.Column('days_of_week', sa.JSON(), nullable=False), sa.Column('action', sa.JSON(), nullable=False), sa.Column('enabled', sa.Boolean(), nullable=False), sa.Column('created_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id']), sa.ForeignKeyConstraint(['user_id'], ['users.id']), sa.PrimaryKeyConstraint('id'))
    if 'schedules' not in existing:
        op.create_index(op.f('ix_schedules_device_id'), 'schedules', ['device_id'], unique=False)
    if 'schedules' not in existing:
        op.create_index(op.f('ix_schedules_user_id'), 'schedules', ['user_id'], unique=False)
    if 'device_profiles' not in existing:
        op.create_table('device_profiles', sa.Column('device_id', sa.Integer(), nullable=False), sa.Column('device_type_id', sa.Integer(), nullable=True), sa.Column('home_id', sa.Integer(), nullable=True), sa.Column('room_id', sa.Integer(), nullable=True), sa.Column('metadata_json', sa.JSON(), nullable=False), sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False), sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'), sa.ForeignKeyConstraint(['device_type_id'], ['device_types.id']), sa.ForeignKeyConstraint(['home_id'], ['homes.id'], ondelete='SET NULL'), sa.ForeignKeyConstraint(['room_id'], ['rooms.id'], ondelete='SET NULL'), sa.PrimaryKeyConstraint('device_id'))
    if 'device_profiles' not in existing:
        op.create_index(op.f('ix_device_profiles_device_type_id'), 'device_profiles', ['device_type_id'], unique=False)
    if 'device_profiles' not in existing:
        op.create_index(op.f('ix_device_profiles_home_id'), 'device_profiles', ['home_id'], unique=False)
    if 'device_profiles' not in existing:
        op.create_index(op.f('ix_device_profiles_room_id'), 'device_profiles', ['room_id'], unique=False)

def downgrade():
    raise RuntimeError('This baseline preserves user data; restore a backup to downgrade.')
