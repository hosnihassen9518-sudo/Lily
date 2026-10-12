import base64, json
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from sqlalchemy import select
from app.models.device import Device
from app.models.device_lifecycle import DeviceIdentity
from app.models.smart_device import DeviceProfile, DeviceState
from app.models.schedule import Schedule
from app.services.device_authorization import public_pem, private_pem
from app.core.security import hash_password, create_pairing_token
from datetime import time

def test_reset_pending_requires_signed_completion(client,db,owner,tmp_path,monkeypatch):
    from app.core.config import settings
    key=ec.generate_private_key(ec.SECP256R1())
    path=tmp_path/'server.pem'; path.write_text(private_pem(key))
    monkeypatch.setattr(settings,'device_signing_key_file',str(path))
    device_key=ec.generate_private_key(ec.SECP256R1())
    device=Device(serial_number='RESET-1',secret_hash=hash_password('factory-secret'),owner_id=owner[0].id,model='test',name='Old name',lifecycle_status='ACTIVE')
    db.add(device); db.flush()
    db.add(DeviceIdentity(device_id=device.id,receipt_public_key=public_pem(device_key.public_key()),protocol_version=1,generation=1))
    db.add(DeviceProfile(device_id=device.id,metadata_json={'model_key':'lily_test_light'}))
    db.add(DeviceState(device_id=device.id,state={'power':True}))
    db.add(Schedule(device_id=device.id,user_id=owner[0].id,name='old',time_of_day=time(9),action={},days_of_week=[]))
    db.commit()
    result=client.post(f'/api/v1/devices/{device.id}/removal',headers=owner[1])
    assert result.status_code==200,result.text
    operation=result.json()
    assert operation['status']=='pending'
    assert client.post(f'/api/v1/devices/{device.id}/removal',headers=owner[1]).json()['operation_id']==operation['operation_id']
    assert client.put(f'/api/v1/devices/{device.id}/light',headers=owner[1],json={'enabled':True,'brightness':50,'r':1,'g':2,'b':3}).status_code==409
    assert client.post('/api/v1/devices/claim',headers=owner[1],json={'serial_number':device.serial_number}).status_code==409
    assert client.post('/api/v1/devices/activate',json={'serial_number':device.serial_number,'device_secret':'factory-secret','pairing_token':create_pairing_token(owner[0].id)}).status_code==409
    body=f'reset|{device.serial_number}|{operation["operation_id"]}|1'
    assert client.post('/api/v1/device-runtime/reset-complete',json={'receipt':{'body':body,'signature':'invalid'}}).status_code==401
    receipt={'body':body,'signature':base64.b64encode(device_key.sign(body.encode(),ec.ECDSA(hashes.SHA256()))).decode()}
    assert client.post('/api/v1/device-runtime/reset-complete',json={'receipt':receipt}).json()['status']=='completed'
    db.refresh(device)
    assert device.owner_id is None and device.name is None and device.lifecycle_status=='INVENTORY'
    assert db.get(DeviceState,device.id) is None
    assert not db.scalars(select(Schedule).where(Schedule.device_id==device.id)).all()
    assert client.get(f'/api/v1/device-operations/{operation["operation_id"]}',headers=owner[1]).json()['status']=='completed'
    assert client.post('/api/v1/device-runtime/reset-complete',json={'receipt':receipt}).status_code==200

def test_invalid_identity_is_validation_error(client,db,owner):
    device=Device(serial_number='KEY-TEST',secret_hash=hash_password('factory-secret'),model='test')
    db.add(device);db.commit()
    response=client.post('/api/v1/device-runtime/register',json={'serial_number':device.serial_number,'device_secret':'factory-secret','receipt_public_key':'invalid','protocol_version':1})
    assert response.status_code==422

def test_admin_cannot_cancel_reset_by_enabling_device(client,db,owner,admin):
    device=Device(serial_number='PENDING-ADMIN',secret_hash='unused',model='test',owner_id=owner[0].id,lifecycle_status='RESET_PENDING')
    db.add(device);db.commit()
    assert client.patch(f'/api/v1/devices/admin/{device.id}/disabled',headers=admin,json={'disabled':False}).status_code==409

def test_claim_waits_for_retained_schedule_cleanup(client,db,owner):
    from app.models.device_lifecycle import DeviceOperation
    device=Device(serial_number='CLEANUP',secret_hash='unused',model='test',lifecycle_status='INVENTORY')
    db.add(device);db.flush()
    db.add(DeviceOperation(id='cleanup-test',device_id=device.id,requested_by_id=owner[0].id,generation=1,status='completed',broker_cleanup_pending=1));db.commit()
    assert client.post('/api/v1/devices/claim',headers=owner[1],json={'serial_number':device.serial_number}).status_code==409

def test_old_firmware_not_unlinked(client,db,owner):
    device=Device(serial_number='OLD',secret_hash='unused',model='old',owner_id=owner[0].id)
    db.add(device);db.commit()
    assert client.post(f'/api/v1/devices/{device.id}/removal',headers=owner[1]).status_code==409
    db.refresh(device); assert device.owner_id==owner[0].id
