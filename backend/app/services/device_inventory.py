from sqlalchemy import select
from app.models.device_lifecycle import DeviceModel, AppSetting
from app.models.smart_device import DeviceType
import json
import secrets
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from app.models.device import Device
from app.models.smart_device import DeviceProfile
from app.models.device_lifecycle import DeviceIdentity
from app.core.security import hash_password
from app.core.config import settings
from app.services.device_authorization import prepare_signing_key, public_pem, private_pem

def c_string(value: str) -> str:
    # Three-digit octal escapes preserve UTF-8 without invalid C surrogate escapes.
    return '"' + ''.join(('\\' + chr(byte)) if byte in (34, 92) else chr(byte) if 32 <= byte < 127 else '\\%03o' % byte for byte in value.encode('utf-8')) + '"'

def create_inventory(db, type_id: int, model_key: str):
    model = db.scalar(select(DeviceModel).where(DeviceModel.key == model_key).with_for_update())
    dtype = db.get(DeviceType, type_id)
    if not model or not dtype or model.device_type_id != type_id:
        raise HTTPException(422, 'Select a supported model for this device type.')
    server_key = prepare_signing_key(db)
    device_key = ec.generate_private_key(ec.SECP256R1())
    secret = 'lily_' + secrets.token_urlsafe(32)
    for attempt in range(5):
        serial = 'LILY-' + secrets.token_hex(8).upper()
        try:
            with db.begin_nested():
                device = Device(serial_number=serial, secret_hash=hash_password(secret), model=model.name,
                                hardware_version=model.hardware_version, lifecycle_status='INVENTORY')
                db.add(device); db.flush()
                db.add(DeviceProfile(device_id=device.id, device_type_id=type_id, metadata_json={'model_key': model_key}))
                db.add(DeviceIdentity(device_id=device.id, receipt_public_key=public_pem(device_key.public_key())))
            break
        except IntegrityError:
            if attempt == 4:
                raise HTTPException(503, 'Could not allocate a unique serial; try again.')
    values = {
        'DEVICE_SERIAL': serial, 'DEVICE_SECRET': secret, 'DEVICE_MODEL': model.name,
        'DEVICE_TYPE_KEY': dtype.key, 'DEVICE_TYPE_NAME': dtype.name,
        'DEVICE_TYPE_AP_TAG': 'TEST-LIGHT' if dtype.key == 'test_light' else 'AUDIO-LIGHT',
        'BACKEND_HOST': settings.factory_backend_host, 'BACKEND_PORT': settings.factory_backend_port,
        'MQTT_HOST': settings.factory_mqtt_host, 'MQTT_PORT': settings.factory_mqtt_port,
        'FIRMWARE_VERSION': '0.8.0-' + dtype.key,
        'DEVICE_SERVER_PUBLIC_KEY': public_pem(server_key.public_key()),
        'DEVICE_RECEIPT_PRIVATE_KEY': private_pem(device_key),
    }
    pins = {'LED_PIN': 18} if dtype.key == 'test_light' else {'RGB_PIN': 4, 'I2S_BCLK_PIN': 12, 'I2S_LRC_PIN': 13, 'I2S_DOUT_PIN': 14, 'MIC_BCLK_PIN': 15, 'MIC_WS_PIN': 16, 'MIC_DATA_PIN': 17}
    if model_key == "lily_led_strip":
        pins.update(LED_COUNT=5, LILY_LED_STRIP=1)
    values.update(pins)
    header = '#pragma once\n\n' + '\n'.join('#define ' + key + ' ' + (str(value) if isinstance(value, int) else c_string(value)) for key, value in values.items()) + '\n'
    from app.services.provisioning_archive import archive_config
    archive_config(db,device.id,{'serial_number':serial,'device_secret':secret,'filename':serial+'-device_config.h','config_header':header})
    db.commit()
    from app.api.devices import serialize_device
    return {'device': serialize_device(device, db), 'serial_number': serial, 'device_secret': secret,
            'filename': serial + '-device_config.h', 'config_header': header}

def seed_models(db):
    for key, name, type_key, target in (
        ('lily_v1', 'LILY-V1', 'lily_audio_light', 'esp32_device'),
        ('lily_test_light', 'Lily Test Light', 'test_light', 'esp32_test_light'),
        ('lily_led_strip', 'Lily LED Strip', 'test_light', 'esp32_test_light'),
    ):
        dtype = db.scalar(select(DeviceType).where(DeviceType.key == type_key))
        if dtype is None:
            dtype = DeviceType(key=type_key, name=name)
            db.add(dtype); db.flush()
        if db.get(DeviceModel, key) is None:
            db.add(DeviceModel(key=key, name=name, device_type_id=dtype.id, firmware_target=target,
                               capabilities=["power", "light", "brightness", "rgb"] if key == "lily_led_strip" else None))
    if db.get(AppSetting, 'mobile_session_months') is None:
        db.add(AppSetting(key='mobile_session_months', value_json={'months': 3}))
    db.flush()
    catalog = db.scalars(select(DeviceModel)).all()
    for device in db.scalars(select(Device)):
        profile = db.get(DeviceProfile, device.id)
        if profile and (profile.metadata_json or {}).get('model_key'): continue
        matches = [model for model in catalog if device.model in (model.key, model.name)]
        if len(matches) != 1: continue
        model = matches[0]
        if profile is None:
            profile = DeviceProfile(device_id=device.id)
            db.add(profile)
        profile.device_type_id = model.device_type_id
        profile.metadata_json = {**(profile.metadata_json or {}), 'model_key':model.key}
    db.commit()
