import json
from types import SimpleNamespace
from app.models.device import Device
from app.models.device_lifecycle import DeviceIdentity
from app.core.security import hash_password

def test_owned_controls_and_schedules_capture_generation(client,db,owner,monkeypatch):
    from app.services.mqtt_service import mqtt_service
    device=Device(serial_number='GEN-TEST',secret_hash=hash_password('factory-secret'),owner_id=owner[0].id,lifecycle_status='ACTIVE',model='test')
    db.add(device);db.flush();db.add(DeviceIdentity(device_id=device.id,generation=7,protocol_version=1,receipt_public_key='unused'));db.commit()
    from app.models.smart_device import DeviceProfile, DeviceType, DeviceTypeCapability
    dtype = DeviceType(key='generation_light', name='Generation Light')
    db.add(dtype); db.flush()
    db.add(DeviceProfile(device_id=device.id, device_type_id=dtype.id))
    for capability in ('power','light','brightness','rgb'):
        db.add(DeviceTypeCapability(device_type_id=dtype.id, capability=capability))
    db.commit()
    messages=[]
    monkeypatch.setattr(mqtt_service,'started',True)
    monkeypatch.setattr(mqtt_service.client,'publish',lambda topic,payload,**kwargs:(messages.append((topic,json.loads(payload))) or SimpleNamespace(rc=0)))
    assert client.put(f'/api/v1/devices/{device.id}/light',headers=owner[1],json={'enabled':True,'brightness':50,'r':1,'g':2,'b':3}).status_code==200
    assert client.post(f'/api/v1/schedules/device/{device.id}',headers=owner[1],json={'name':'Morning','time_of_day':'09:00','days_of_week':[1],'action':{'light':{'enabled':True}},'enabled':True}).status_code==200
    assert len(messages)==2
    assert all(payload.get('generation')==7 for _,payload in messages)

def test_stale_reports_do_not_restore_previous_owner_state(db,owner,monkeypatch):
    import app.services.mqtt_service as module
    from sqlalchemy.orm import Session
    device=Device(serial_number='GEN-REPORT',secret_hash='unused',owner_id=owner[0].id,lifecycle_status='ACTIVE',model='test',brightness=100)
    db.add(device);db.flush();db.add(DeviceIdentity(device_id=device.id,generation=2,protocol_version=1,receipt_public_key='unused'));db.commit()
    monkeypatch.setattr(module,'SessionLocal',lambda:Session(db.get_bind()))
    def report(generation,brightness):
        module.mqtt_service._on_message(None,None,SimpleNamespace(topic='devices/GEN-REPORT/state',payload=json.dumps({'generation':generation,'light':{'brightness':brightness}}).encode()))
    report(1,10)
    db.expire_all();assert db.get(Device,device.id).brightness==100
    report(2,60)
    db.expire_all();assert db.get(Device,device.id).brightness==60
