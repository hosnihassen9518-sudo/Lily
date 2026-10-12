from sqlalchemy import select
from app.models.device import Device
from app.models.smart_device import DeviceType
from app.core.security import verify_password
from app.services.device_inventory import seed_models
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

def test_inventory_generation_and_no_secret_in_lists(client, db, admin, monkeypatch, tmp_path):
    from app.core.config import settings
    key = ec.generate_private_key(ec.SECP256R1())
    path = tmp_path / 'signing.pem'
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    monkeypatch.setattr(settings, 'device_signing_key_file', str(path), raising=False)
    seed_models(db)
    dtype = db.scalar(select(DeviceType).where(DeviceType.key == 'test_light'))
    response = client.post('/api/v1/admin/device-inventory', headers=admin, json={'device_type_id': dtype.id, 'model_key': 'lily_test_light'})
    assert response.status_code == 200, response.text
    result = response.json()
    device = db.get(Device, result['device']['id'])
    assert verify_password(result['device_secret'], device.secret_hash)
    assert f'#define DEVICE_SERIAL "{device.serial_number}"' in result['config_header']
    assert '#define LED_PIN' in result['config_header']
    assert 'DEVICE_RECEIPT_PRIVATE_KEY' in result['config_header']
    assert result['device_secret'] not in client.get('/api/v1/devices/admin/all', headers=admin).text
    assert client.post('/api/v1/admin/device-inventory', headers=admin, json={'device_type_id': dtype.id, 'model_key': 'lily_v1'}).status_code == 422

def test_activation_does_not_replace_factory_type(client, db, owner):
    from app.models.smart_device import DeviceProfile
    from app.core.security import hash_password, create_pairing_token
    seed_models(db)
    dtype = db.scalar(select(DeviceType).where(DeviceType.key == 'test_light'))
    device = Device(serial_number='TYPE-TEST', secret_hash=hash_password('factory-secret'), model='test')
    db.add(device); db.flush()
    db.add(DeviceProfile(device_id=device.id, device_type_id=dtype.id)); db.commit()
    response = client.post('/api/v1/devices/activate', json={'serial_number':device.serial_number, 'device_secret':'factory-secret', 'pairing_token':create_pairing_token(owner[0].id), 'device_type_key':'lily_audio_light'})
    assert response.status_code == 409

def test_inventory_requires_admin(client, owner):
    assert client.post('/api/v1/admin/device-inventory', headers=owner[1], json={'device_type_id': 1, 'model_key': 'lily_v1'}).status_code == 403

def test_header_string_escaping_compiles_and_preserves_unicode(tmp_path):
    import subprocess
    from app.services.device_inventory import c_string
    value='Bedroom 💡 "light"\n'
    source=tmp_path/'header.cpp'
    source.write_text('#include <cstdio>\nint main(){std::printf("%s",'+c_string(value)+');}\n')
    binary=tmp_path/'header-test'
    subprocess.run(['g++',str(source),'-o',str(binary)],check=True)
    assert subprocess.check_output([str(binary)])==value.encode()
