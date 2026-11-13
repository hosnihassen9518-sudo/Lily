from app.models.device_lifecycle import DeviceModel
from app.models.device_provisioning import UsbProvisioning
from app.services.device_inventory import seed_models


USB = '/api/v1/admin/usb-flash'
BOARD = {'chip': 'ESP32-S3', 'flash_size': 16 * 1024 * 1024, 'mac': '12:34:56:78:90:AB'}


def test_factory_package_retries_keep_one_identity(client, db, admin, owner, monkeypatch):
    from app.services import usb_firmware

    seed_models(db)
    builds = []

    def build(model_key, serial, header, *, factory, partition_sha256):
        assert f'#define DEVICE_SERIAL "{serial}"' in header
        builds.append(serial)
        return {'serial_number': serial, 'model_key': model_key, 'segments': []}

    monkeypatch.setattr(usb_firmware, 'require_builder', lambda: None)
    monkeypatch.setattr(usb_firmware, 'build_package', build)
    payload = {**BOARD, 'mode': 'blank', 'model_key': 'lily_v2'}
    assert client.post(f'{USB}/package', json=payload, headers=owner[1]).status_code == 403
    assert client.post(f'{USB}/package', json={**payload, 'resume': True}, headers=admin).status_code == 409
    first = client.post(f'{USB}/package', json=payload, headers=admin)
    assert first.status_code == 200, first.text
    assert first.headers['cache-control'] == 'no-store'
    retry = client.post(f'{USB}/package', json={**payload, 'resume': True}, headers=admin)
    assert retry.json() == first.json()
    serial = first.json()['serial_number']
    assert builds == [serial]
    binding = db.get(UsbProvisioning, '1234567890ab')
    assert binding.pending_package and serial.encode() not in binding.pending_package
    lookup = client.get(f'{USB}/devices/{serial}', params={'mac': BOARD['mac']}, headers=admin)
    assert lookup.json()['model_key'] == 'lily_v2'
    assert client.get(f'{USB}/devices/{serial}', params={'mac': '1234567890ac'}, headers=admin).status_code == 409
    completion = {'serial_number': serial, 'mac': BOARD['mac'], 'mode': 'blank',
                  'completion_token': first.json()['completion_token']}
    assert client.post(f'{USB}/complete', json={**completion, 'mode': 'keep'}, headers=admin).status_code == 409
    done = client.post(f'{USB}/complete', json=completion, headers=admin)
    assert done.status_code == 200
    assert client.post(f'{USB}/complete', json=completion, headers=admin).status_code == 200
    db.refresh(binding)
    assert binding.pending_package is None


def test_kids_models_have_distinct_catalog_images(client, db, admin):
    seed_models(db)
    light = db.get(DeviceModel, 'lily_led_strip')
    speaker = db.get(DeviceModel, 'lily_v2')
    assert (light.theme_key, light.image_key) == ('kids', 'lily-light')
    assert (speaker.theme_key, speaker.image_key) == ('kids', 'lily-speaker')
    assert 'audio' not in light.capabilities
    assert 'audio' in speaker.capabilities
    models = client.get(f'{USB}/models', headers=admin)
    assert models.status_code == 200
    assert {entry['key'] for entry in models.json()} == {'lily_led_strip', 'lily_v2'}


def test_admin_reset_keeps_serial_and_waits_for_device_receipt(client, db, owner, admin):
    from app.models.device import Device
    from app.models.device_lifecycle import DeviceIdentity
    from app.services.device_inventory import create_inventory

    seed_models(db)
    model = db.get(DeviceModel, 'lily_v2')
    inventory = create_inventory(db, model.device_type_id, model.key)
    device = db.get(Device, inventory['device']['id'])
    serial = device.serial_number
    request = {'serial_number': serial, 'mac': BOARD['mac']}
    assert client.post(f'{USB}/reset', json=request, headers=admin).status_code == 409
    device.owner_id = owner[0].id
    device.lifecycle_status = 'ACTIVE'
    db.get(DeviceIdentity, device.id).protocol_version = 1
    db.commit()
    assert client.post(f'{USB}/reset', json=request, headers=owner[1]).status_code == 403
    reset = client.post(f'{USB}/reset', json=request, headers=admin)
    assert reset.status_code == 200, reset.text
    assert reset.json()['status'] == 'pending'
    assert client.post(f'{USB}/reset', json=request, headers=admin).json() == reset.json()
    db.refresh(device)
    assert device.owner_id == owner[0].id
    assert device.serial_number == serial
    assert client.post(f'{USB}/package', json={**BOARD, 'mode': 'reset', 'serial_number': serial,
                                              'partition_sha256': 'a' * 64}, headers=admin).status_code == 409


def test_interrupted_update_reuses_staged_image_and_identity(client, db, admin, monkeypatch):
    from app.services import usb_firmware
    from app.services.device_inventory import create_inventory

    seed_models(db)
    model = db.get(DeviceModel, 'lily_v2')
    serial = create_inventory(db, model.device_type_id, model.key)['serial_number']
    digest = 'a' * 64
    payload = {**BOARD, 'mode': 'keep', 'serial_number': serial, 'partition_sha256': digest}
    calls = []

    def build(model_key, serial, header, *, factory, partition_sha256):
        assert not factory
        calls.append(serial)
        return {'serial_number': serial, 'model_key': model_key, 'partition_sha256': partition_sha256,
                'segments': [{'address': 0x10000}]}

    monkeypatch.setattr(usb_firmware, 'build_package', build)
    assert client.post(f'{USB}/package', json={**payload, 'resume': True}, headers=admin).status_code == 409
    first = client.post(f'{USB}/package', json=payload, headers=admin)
    assert first.status_code == 200, first.text
    recovery = client.get(f"{USB}/recovery/{BOARD['mac']}", headers=admin)
    assert recovery.json()['partition_sha256'] == digest
    assert recovery.json()['serial_number'] == serial
    assert client.post(f'{USB}/package', json={**payload, 'resume': True, 'partition_sha256': 'b' * 64}, headers=admin).status_code == 409
    assert client.post(f'{USB}/package', json={**payload, 'resume': True}, headers=admin).json() == first.json()
    assert calls == [serial]
    confirmation = {'mode': 'keep', 'serial_number': serial, 'mac': BOARD['mac'],
                    'completion_token': first.json()['completion_token']}
    assert client.post(f'{USB}/complete', json={**confirmation, 'completion_token': '0' * 64}, headers=admin).status_code == 409
    assert client.post(f'{USB}/complete', json=confirmation, headers=admin).status_code == 200
    assert client.get(f"{USB}/recovery/{BOARD['mac']}", headers=admin).json() is None
