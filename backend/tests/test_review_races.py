import base64
from datetime import datetime,timezone
from sqlalchemy.orm import Session
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from fastapi import HTTPException
import pytest
from app.models.user import User
from app.models.device import Device
from app.models.device_lifecycle import DeviceIdentity,DeviceOperation
from app.core.security import hash_password,create_pairing_token
from app.schemas.device import DeviceActivate
from app.services.device_authorization import public_pem
from app.api.devices import activate_device

def inventory(db,owner):
    second=User(email='second@test.org',password_hash='unused',is_active=True);db.add(second);db.flush()
    device=Device(serial_number='RACE-TEST',secret_hash=hash_password('factory-secret'),model='test',lifecycle_status='INVENTORY')
    db.add(device);db.flush()
    key=ec.generate_private_key(ec.SECP256R1())
    db.add(DeviceIdentity(device_id=device.id,receipt_public_key=public_pem(key.public_key()),protocol_version=1,generation=0));db.commit()
    return device,second,key

def activation(device,user):
    return DeviceActivate(serial_number=device.serial_number,device_secret='factory-secret',pairing_token=create_pairing_token(user.id))

def test_stale_activation_cannot_overwrite_current_owner(db,owner):
    device,second,key=inventory(db,owner)
    with Session(db.get_bind(),expire_on_commit=False) as delayed:
        held_device=delayed.get(Device,device.id)
        assert held_device.owner_id is None
        activate_device(activation(device,second),db=db)
        with pytest.raises(HTTPException) as rejected:
            activate_device(activation(device,owner[0]),db=delayed)
        assert rejected.value.status_code==409
    db.expire_all();assert db.get(Device,device.id).owner_id==second.id

def test_stale_duplicate_receipt_preserves_reassigned_device(db,owner,monkeypatch):
    from app.api.device_operations import reset_complete,Completion
    from app.services.mqtt_service import mqtt_service
    monkeypatch.setattr(mqtt_service,'clear_device_retained',lambda serial:True)
    device,second,key=inventory(db,owner)
    device.owner_id=owner[0].id;device.lifecycle_status='RESET_PENDING'
    identity=db.get(DeviceIdentity,device.id);identity.generation=1
    op=DeviceOperation(id='a'*32,device_id=device.id,requested_by_id=owner[0].id,generation=1,status='pending')
    db.add(op);db.commit()
    body=f'reset|{device.serial_number}|{op.id}|1'
    receipt=Completion(receipt={'body':body,'signature':base64.b64encode(key.sign(body.encode(),ec.ECDSA(hashes.SHA256()))).decode()})
    with Session(db.get_bind(),expire_on_commit=False) as delayed:
        held_op=delayed.get(DeviceOperation,op.id);held_device=delayed.get(Device,device.id);held_identity=delayed.get(DeviceIdentity,device.id)
        reset_complete(receipt,db=db)
        from app.api.device_operations import cleanup_retained_operation
        assert cleanup_retained_operation(db,op.id)
        activate_device(activation(device,second),db=db)
        assert held_op.status=='pending' and held_device.owner_id==owner[0].id and held_identity.generation==1
        reset_complete(receipt,db=delayed)
    db.expire_all()
    current=db.get(Device,device.id)
    assert current.owner_id==second.id and current.lifecycle_status=='ACTIVE'
    assert db.get(DeviceIdentity,device.id).generation==2

def test_cleanup_retries_without_reconnect(db,owner,monkeypatch):
    import app.services.mqtt_service as module
    service=module.mqtt_service
    device,second,key=inventory(db,owner)
    op=DeviceOperation(id='b'*32,device_id=device.id,requested_by_id=owner[0].id,generation=0,status='completed',broker_cleanup_pending=1)
    db.add(op);db.commit()
    healthy=False
    monkeypatch.setattr(module,'SessionLocal',lambda:Session(db.get_bind()))
    monkeypatch.setattr(service.client,'is_connected',lambda:True)
    monkeypatch.setattr(service,'clear_device_retained',lambda serial:healthy)
    service.retry_pending_cleanup()
    db.expire_all();assert db.get(DeviceOperation,op.id).broker_cleanup_pending==1
    healthy=True
    service.retry_pending_cleanup()
    db.expire_all();assert db.get(DeviceOperation,op.id).broker_cleanup_pending==0
