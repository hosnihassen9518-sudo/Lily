"""Factory model feature resolution and shared control authorization."""
from fastapi import HTTPException
from sqlalchemy import select
from app.models.device_lifecycle import DeviceModel
from app.models.smart_device import DeviceProfile, DeviceTypeCapability

FEATURES = [
    {'key': key, 'name': name, 'description': description}
    for key, name, description in (
        ('power', 'Power', 'Turn the device on or off.'),
        ('light', 'Light', 'Control the light.'),
        ('brightness', 'Brightness', 'Adjust light brightness.'),
        ('rgb', 'Color', 'Choose the light color.'),
        ('audio', 'Audio', 'Load and play audio.'),
        ('volume', 'Volume', 'Adjust audio volume.'),
    )
]

def validate_capabilities(caps):
    if caps is None: return None
    if any(c not in {f['key'] for f in FEATURES} for c in caps):
        raise HTTPException(422, 'Unknown device feature')
    dependencies = {'light': 'power', 'brightness': 'light', 'rgb': 'light', 'volume': 'audio'}
    for feature, dependency in dependencies.items():
        if feature in caps and dependency not in caps:
            raise HTTPException(422, f'{feature} requires {dependency}')
    return sorted(set(caps))

def associated_model(db, device):
    profile = db.get(DeviceProfile, device.id)
    key = (profile.metadata_json or {}).get('model_key') if profile else None
    if key: return db.get(DeviceModel, key)
    # Legacy factory names identify only an unambiguous catalog entry.
    rows = db.scalars(select(DeviceModel).where(DeviceModel.name == device.model)).all()
    if len(rows) == 1: return rows[0]
    return db.get(DeviceModel, device.model)

def legacy_capabilities(caps):
    values = set(caps)
    if 'power' in values and values.intersection({'brightness', 'rgb'}): values.add('light')
    if 'light' in values: values.add('power')
    return sorted(values)

def model_capabilities(db, model):
    if model.capabilities is not None: return list(model.capabilities)
    return legacy_capabilities(db.scalars(select(DeviceTypeCapability.capability).where(
        DeviceTypeCapability.device_type_id == model.device_type_id)).all())

def effective_capabilities(db, device):
    model = associated_model(db, device)
    if model: return model_capabilities(db, model)
    profile = db.get(DeviceProfile, device.id)
    if profile and profile.device_type_id:
        return legacy_capabilities(db.scalars(select(DeviceTypeCapability.capability).where(
            DeviceTypeCapability.device_type_id == profile.device_type_id)).all())
    return []

def require_features(db, device, *features):
    caps = effective_capabilities(db, device)
    for feature in features:
        if feature not in caps: raise HTTPException(403, f'Device does not support {feature}')

def validate_state(db, device, state):
    mapping = {'enabled':'power','power':'power','light':'light','light_on':'light',
               'brightness':'brightness','r':'rgb','g':'rgb','b':'rgb','rgb':'rgb','color':'rgb',
               'volume':'volume','audio':'audio','playing':'audio','audio_playing':'audio',
               'current_track_title':'audio'}
    for key, value in state.items():
        if key not in mapping: raise HTTPException(422, f'Unsupported control field: {key}')
        require_features(db, device, mapping[key])
        if key == 'current_track_title' and (not isinstance(value, str) or len(value) > 255):
            raise HTTPException(422, 'Track title must be text of at most 255 characters')
        if isinstance(value, dict): validate_state(db, device, value)

def validate_command(db, device, command):
    kind = command.get('type')
    if kind is None:
        validate_state(db, device, command)
        return
    if set(command) - {'type', 'payload'}: raise HTTPException(422, 'Mixed command shapes are not supported')
    payload = command.get('payload') or {}
    if not isinstance(payload, dict): raise HTTPException(422, 'Command payload must be an object')
    feature = {'light':'light','power':'power','volume':'volume','audio_play':'audio',
               'audio_stop':'audio','audio_load':'audio','audio':'audio','audio_download':'audio'}.get(kind)
    if not feature: raise HTTPException(422, 'Unsupported device command')
    require_features(db, device, feature)
    if kind in ('audio_load','audio_download'):
        if set(payload) - {'url','music_id','filename'}: raise HTTPException(422, 'Unsupported audio field')
    else: validate_state(db, device, payload)

def light_payload(db, device, fields):
    require_features(db, device, 'light')
    validate_state(db, device, fields)
    return {'enabled': fields.get('enabled', device.light_on),
            'brightness': fields.get('brightness', device.brightness),
            'r': fields.get('r', device.color_r), 'g': fields.get('g', device.color_g),
            'b': fields.get('b', device.color_b)}

def schedule_action(db, device, action):
    if not isinstance(action, dict) or not action: raise HTTPException(422, 'Schedule needs an action')
    if 'type' in action:
        validate_command(db, device, action)
        kind, payload = action['type'], action.get('payload') or {}
        if kind == 'light': action = {'light': payload}
        elif kind in ('audio_play', 'audio_stop'): action = {'audio': 'play' if kind == 'audio_play' else 'stop'}
        elif kind == 'volume' and 'volume' in payload: action = {'volume': payload['volume']}
        else: raise HTTPException(422, 'Command is not supported in schedules')
    if set(action) - {'light', 'audio', 'volume'}: raise HTTPException(422, 'Unsupported schedule field')
    validate_state(db, device, action)
    result = dict(action)
    if 'light' in result:
        if not isinstance(result['light'], dict): raise HTTPException(422, 'Light action must be an object')
        result['light'] = light_payload(db, device, result['light'])
    if 'audio' in result and result['audio'] not in ('play', 'stop'): raise HTTPException(422, 'Invalid audio action')
    if 'volume' in result and (type(result['volume']) is not int or not 0 <= result['volume'] <= 100):
        raise HTTPException(422, 'Invalid schedule volume')
    return result
