from app.models.music import Music
from app.models.device_lifecycle import DeviceIdentity, DeviceModel
from app.services.device_inventory import seed_models, create_inventory
from test_device_features import model_device


def test_v2_factory_pins(db):
    seed_models(db)
    model = db.get(DeviceModel, 'lily_v2')
    assert model is not None
    header = create_inventory(db, model.device_type_id, model.key)['config_header']
    for definition in ['RGB_PIN 18', 'LED_COUNT 5', 'I2S_BCLK_PIN 10',
                       'I2S_LRC_PIN 40', 'I2S_DOUT_PIN 15']:
        assert '#define ' + definition in header


def test_catalog_command_and_scoped_media(client, db, owner, monkeypatch, tmp_path):
    device, _ = model_device(db, owner, ['audio', 'volume'])
    device.firmware_version = '2.0.0'; db.commit()
    path = tmp_path / 'song.mp3'
    path.write_bytes(b'ID3-test-audio')
    track = Music(title='Song', filename='song.mp3', storage_path=str(path),
                  filesize=14, checksum_sha256='a' * 64)
    db.add(track); db.commit()
    sent = []
    from app.services.mqtt_service import mqtt_service
    monkeypatch.setattr(mqtt_service, 'publish_command',
                        lambda serial, command, **kw: sent.append(command) or True)
    base = f'/api/v1/devices/{device.id}/audio/catalog'
    assert client.post(base, json={'music_id': track.id}, headers=owner[1]).status_code == 200
    command = sent[-1]
    assert command['type'] == 'audio_catalog'
    assert command['payload']['mode'] == 'auto'
    assert command['payload']['size'] == 14
    url = command['payload']['path']
    assert client.get(url).content == path.read_bytes()
    assert client.get(url.split('?')[0]).status_code == 422
    assert client.get(url + 'tampered').status_code == 403
    device.lifecycle_status = 'RESET_PENDING'; db.commit()
    assert client.get(url).status_code == 403
    assert client.post(base, json={'music_id': track.id}, headers=owner[1]).status_code == 409


def test_old_firmware_requires_upgrade(client, db, owner):
    device, _ = model_device(db, owner, ['audio'])
    device.firmware_version = '0.9.0'; db.commit()
    response = client.post(f'/api/v1/devices/{device.id}/audio/catalog',
                           json={'music_id': 1}, headers=owner[1])
    assert response.status_code == 409
    assert 'v2' in response.json()['detail']


def test_strip_can_upgrade_to_v2_without_changing_identity(client, db, owner, admin):
    seed_models(db)
    model = db.get(DeviceModel, 'lily_led_strip')
    result = create_inventory(db, model.device_type_id, model.key)
    from app.models.device import Device
    device = db.get(Device, result['device']['id'])
    device.owner_id = owner[0].id; device.lifecycle_status = 'ACTIVE'; db.commit()
    serial = device.serial_number
    response = client.patch(f'/api/v1/devices/admin/{device.id}/model',
                            json={'model_key': 'lily_v2'}, headers=admin)
    assert response.status_code == 200
    assert response.json()['serial_number'] == serial
    assert 'audio' in response.json()['smart_home']['capabilities']


def test_catalog_permissions_modes_and_expiry(client, db, owner, tmp_path):
    device, model = model_device(db, owner, [])
    base = f'/api/v1/devices/{device.id}/audio/catalog'
    assert client.post(base, json={'music_id': 1}, headers=owner[1]).status_code == 403
    assert client.post(base, json={'music_id': 1, 'mode': 'ble'}, headers=owner[1]).status_code == 422
    from app.core.security import create_access_token
    assert client.get('/api/v1/music/1/device.mp3?token=' + create_access_token('1')).status_code == 403


def test_media_expiry_generation_and_ownership(client, db, owner, tmp_path):
    from app.services.audio_catalog import media_token
    from app.core.security import decode_token, ALGORITHM
    from app.core.config import settings
    from jose import jwt
    device, _ = model_device(db, owner, ['audio'])
    identity = DeviceIdentity(device_id=device.id, generation=3, protocol_version=1)
    db.add(identity); db.commit()
    token = media_token(device, 3, 1)
    path = '/api/v1/music/1/device.mp3?token='
    expired = decode_token(token); expired['exp'] = 1
    assert client.get(path + jwt.encode(expired, settings.secret_key, algorithm=ALGORITHM)).status_code == 403
    identity.generation = 4; db.commit()
    assert client.get(path + token).status_code == 403
    identity.generation = 3; device.owner_id = None; db.commit()
    assert client.get(path + token).status_code == 403
