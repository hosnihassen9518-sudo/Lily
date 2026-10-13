from app.models.device import Device
from app.models.device_lifecycle import DeviceModel
from app.models.smart_device import DeviceType, DeviceTypeCapability, DeviceProfile


def model_device(db, owner, capabilities):
    dtype = DeviceType(key='feature_test', name='Feature Test')
    db.add(dtype); db.flush()
    db.add(DeviceTypeCapability(device_type_id=dtype.id, capability='light'))
    model = DeviceModel(key='feature_test', name='Feature Test', device_type_id=dtype.id,
                        firmware_target='esp32_device', capabilities=capabilities)
    db.add(model)
    device = Device(serial_number='FEATURE-TEST', secret_hash='unused', owner_id=owner[0].id,
                    lifecycle_status='ACTIVE', brightness=41)
    db.add(device); db.flush()
    db.add(DeviceProfile(device_id=device.id, device_type_id=dtype.id,
                         metadata_json={'model_key': model.key}))
    db.commit()
    return device, model


def test_empty_model_denies_all_controls(client, db, owner):
    device, model = model_device(db, owner, [])
    base = f'/api/v1/devices/{device.id}'
    assert client.get('/api/v1/devices', headers=owner[1]).json()[0]['smart_home']['capabilities'] == []
    for path, method, body in [('/light','put',{'enabled':True}), ('/audio/play','post',None),
                               ('/audio/volume','put',{'volume':40}),
                               ('/command','post',{'type':'power','payload':{'enabled':True}}),
                               ('/state','put',{'state':{'enabled':True}})]:
        assert getattr(client, method)(base+path, headers=owner[1], json=body).status_code == 403


def test_light_omitted_fields_and_model_identity(client, db, owner, monkeypatch):
    device, model = model_device(db, owner, ['power','light'])
    from app.services.mqtt_service import mqtt_service
    sent=[]
    monkeypatch.setattr(mqtt_service,'publish_command',lambda serial, command, **kw: sent.append(command) or True)
    base=f'/api/v1/devices/{device.id}'
    assert client.put(base+'/light',headers=owner[1],json={'enabled':True}).status_code == 200
    assert sent[0]['payload']['brightness'] == 41
    assert client.put(base+'/light',headers=owner[1],json={'enabled':True,'brightness':20}).status_code == 403
    assert client.put(base+'/profile',headers=owner[1],json={'metadata':{'model_key':'lily_v1'}}).status_code == 409
    assert client.put(base+'/profile',headers=owner[1],json={'device_type_id':None}).status_code == 409


def test_admin_models_catalog_validation_and_deletion(client, db, admin, owner):
    device, model = model_device(db, owner, None)
    base='/api/v1/admin/device-models'
    assert client.get('/api/v1/admin/device-features',headers=admin).status_code == 200
    assert client.get(base,headers=owner[1]).status_code == 403
    assert client.patch(base+'/'+model.key,headers=admin,json={'capabilities':['volume']}).status_code == 422
    assert client.patch(base+'/'+model.key,headers=admin,json={'capabilities':[]}).status_code == 200
    assert client.delete(base+'/'+model.key,headers=admin).status_code == 409
    payload={'key':'new_model','name':'New','device_type_id':model.device_type_id,
             'hardware_version':'1.0','firmware_target':'esp32_device','capabilities':['power']}
    assert client.post(base,headers=admin,json=payload).status_code == 200
    assert client.delete(base+'/new_model',headers=admin).status_code == 200


def test_inheritance_and_seed_preserve_model_edits(db, owner):
    from app.services.device_features import effective_capabilities
    from app.services.device_inventory import seed_models
    device, model = model_device(db, owner, None)
    assert effective_capabilities(db, device) == ['light','power']
    model.capabilities = []
    db.commit(); seed_models(db)
    assert effective_capabilities(db, device) == []


def test_schedule_and_widget_deny_empty_model(client, db, owner):
    from app.api.widgets import projection
    device, model = model_device(db, owner, [])
    device.is_online = True; db.commit()
    assert projection(db, device)['can_control'] is False
    response=client.post(f'/api/v1/schedules/device/{device.id}',headers=owner[1],json={
        'name':'Denied','time_of_day':'09:00','days_of_week':[0],'action':{'light':{'enabled':True}}})
    assert response.status_code == 403


def test_backfill_preserves_location_and_metadata(db, owner):
    from app.models.home import Home, Room
    from app.services.device_inventory import seed_models
    home=Home(owner_id=owner[0].id,name='Family'); db.add(home); db.flush()
    room=Room(home_id=home.id,name='Bedroom'); db.add(room); db.flush()
    device=Device(serial_number='LEGACY-MODEL',secret_hash='original',model='LILY-V1')
    db.add(device); db.flush()
    profile=DeviceProfile(device_id=device.id,home_id=home.id,room_id=room.id,metadata_json={'custom':'saved'})
    db.add(profile); db.commit(); seed_models(db)
    assert (profile.home_id,profile.room_id)==(home.id,room.id)
    assert profile.metadata_json=={'custom':'saved','model_key':'lily_v1'}
    assert device.secret_hash=='original'


def test_schedule_revalidates_after_feature_removal(client, db, owner, monkeypatch):
    from app.api.schedules import sync_device_schedule
    from app.services.mqtt_service import mqtt_service
    device, model = model_device(db, owner, ['power','light'])
    sent=[]
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda serial, payload, **kw: sent.append(payload) or True)
    response=client.post(f'/api/v1/schedules/device/{device.id}',headers=owner[1],json={
        'name':'Morning','time_of_day':'09:00','days_of_week':[0],'action':{'light':{'enabled':True}}})
    assert response.status_code == 200
    assert sent[-1]['schedules'][0]['action']['light']['brightness'] == 41
    model.capabilities=[]; db.commit()
    sync_device_schedule(db, device)
    assert sent[-1]['schedules'] == []


def test_reviewed_schedule_and_music_contracts(client, db, owner, admin, monkeypatch):
    from app.services.mqtt_service import mqtt_service
    device, model = model_device(db, owner, ['power','light','audio'])
    sent=[]
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda serial, payload, **kw: sent.append(payload) or True)
    base=f'/api/v1/schedules/device/{device.id}'
    mixed={'type':'light','payload':{'enabled':True},'audio':'play','volume':100}
    assert client.post(base,headers=owner[1],json={'name':'Mixed','time_of_day':'09:00','days_of_week':[0],'action':mixed}).status_code==422
    typed={'type':'light','payload':{'enabled':True}}
    assert client.post(base,headers=owner[1],json={'name':'Typed','time_of_day':'09:00','days_of_week':[0],'action':typed}).status_code==200
    assert sent[-1]['schedules'][0]['action']['light']['enabled'] is True
    assert 'type' not in sent[-1]['schedules'][0]['action']
    state=f'/api/v1/devices/{device.id}/state'
    assert client.put(state,headers=owner[1],json={'state':{'current_track_title':'Lullaby'}}).status_code==200
    assert client.put(state,headers=owner[1],json={'state':{'current_track_title':123}}).status_code==422
    response=client.patch('/api/v1/admin/device-models/'+model.key,headers=admin,json={'capabilities':[]})
    assert response.status_code==200
    assert sent[-1]['schedules']==[]
    assert client.put(state,headers=owner[1],json={'state':{'current_track_title':'Lullaby'}}).status_code==403


def test_legacy_smart_light_canonicalization(db, owner):
    from app.services.device_features import effective_capabilities, light_payload
    device, model=model_device(db, owner, None)
    from sqlalchemy import delete
    db.execute(delete(DeviceTypeCapability).where(DeviceTypeCapability.device_type_id==model.device_type_id))
    for key in ('power','brightness','rgb'): db.add(DeviceTypeCapability(device_type_id=model.device_type_id,capability=key))
    db.commit()
    assert set(effective_capabilities(db,device))=={'power','light','brightness','rgb'}
    assert light_payload(db,device,{'enabled':True})['enabled'] is True

def test_model_rename_keeps_legacy_device_identity(client, db, owner, admin):
    device, model = model_device(db, owner, ['power','light'])
    device.model = model.name
    profile = db.get(DeviceProfile, device.id)
    profile.metadata_json = {'custom':'keep'}
    db.commit()
    response = client.patch('/api/v1/admin/device-models/'+model.key, headers=admin,
                            json={'name':'Renamed model','capabilities':[]})
    assert response.status_code == 200
    db.refresh(profile)
    assert profile.metadata_json == {'custom':'keep','model_key':model.key}
    from app.services.device_features import effective_capabilities
    assert effective_capabilities(db,device) == []

def test_failed_model_schedule_sync_retries_after_broker_reconnect(client, db, owner, admin, monkeypatch):
    from app.services.mqtt_service import mqtt_service
    from app.models.device_lifecycle import AppSetting
    from app.services.feature_schedule_sync import pending_key
    device, model = model_device(db, owner, ['power','light'])
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda *a,**kw: False)
    response = client.patch('/api/v1/admin/device-models/'+model.key,headers=admin,json={'capabilities':[]})
    assert response.json()['schedule_sync_pending'] == [device.id]
    assert db.get(AppSetting,pending_key(device)) is not None
    from sqlalchemy.orm import Session
    import app.services.mqtt_service as module
    monkeypatch.setattr(module,'SessionLocal',lambda:Session(db.get_bind()))
    monkeypatch.setattr(mqtt_service.client,'is_connected',lambda:True)
    sent=[]
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda serial,payload,**kw: sent.append(payload) or True)
    mqtt_service.retry_pending_cleanup()
    db.expire_all()
    assert db.get(AppSetting,pending_key(device)) is None
    assert sent[-1]['schedules'] == []
