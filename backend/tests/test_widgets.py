from datetime import datetime,timedelta,timezone
from app.models.user import User
from app.models.device import Device
from app.models.device_lifecycle import MobileSession
from app.core.security import hash_password,decode_token


def credentials(client,db):
    user=User(email='widget@test.org',password_hash=hash_password('longpassword'),is_active=True)
    db.add(user);db.commit()
    login=client.post('/api/v1/auth/mobile/login',json={'email':user.email,'password':'longpassword'}).json()
    headers={'Authorization':'Bearer '+login['access_token']}
    issue=client.post('/api/v1/widgets/session',headers=headers,json={'installation_id':'a'*32})
    assert issue.status_code==200,issue.text
    return user,login,headers,issue.json()


def test_widget_token_restricted_and_parent_logout_revokes(client,db):
    user,login,headers,widget=credentials(client,db)
    wh={'Authorization':'Bearer '+widget['token']}
    assert widget['expires_at']==login['session_expires_at']
    assert client.get('/api/v1/widgets/devices',headers=wh).status_code==200
    assert client.get('/api/v1/auth/me',headers=wh).status_code==401
    second=client.post('/api/v1/widgets/session',headers=headers,json={'installation_id':'a'*32}).json()
    assert second['token']==widget['token']
    client.post('/api/v1/auth/mobile/logout',json={'refresh_token':login['refresh_token']})
    assert client.get('/api/v1/widgets/devices',headers=wh).status_code==401


def test_widget_power_checks_owner_state_and_session_expiry(client,db,monkeypatch):
    user,login,headers,widget=credentials(client,db)
    wh={'Authorization':'Bearer '+widget['token']}
    device=Device(serial_number='WIDGET-DEVICE',secret_hash='unused',owner_id=user.id,lifecycle_status='ACTIVE',is_online=True,brightness=23,color_r=10,color_g=11,color_b=12)
    db.add(device);db.commit()
    from app.models.smart_device import DeviceProfile, DeviceType, DeviceTypeCapability
    dtype = DeviceType(key='widget_light', name='Widget Light')
    db.add(dtype); db.flush()
    db.add(DeviceProfile(device_id=device.id, device_type_id=dtype.id))
    for capability in ('power','light'):
        db.add(DeviceTypeCapability(device_type_id=dtype.id, capability=capability))
    db.commit()
    from app.services.mqtt_service import mqtt_service
    messages=[]
    monkeypatch.setattr(mqtt_service,'publish_command',lambda serial,payload,**kwargs:(messages.append(payload) or True))
    response=client.post(f'/api/v1/widgets/devices/{device.id}/power',headers=wh,json={'enabled':True,'expected_generation':None})
    assert response.status_code==200 and response.json()['mqtt_published']
    assert messages[0]['payload']=={'enabled':True,'brightness':23,'r':10,'g':11,'b':12}
    device.lifecycle_status='RESET_PENDING';db.commit()
    assert client.post(f'/api/v1/widgets/devices/{device.id}/power',headers=wh,json={'enabled':False,'expected_generation':None}).status_code==409
    snapshot=client.get('/api/v1/widgets/devices',headers=wh).json()
    assert not snapshot['devices'][0]['can_control']
    device.lifecycle_status='ACTIVE';device.is_online=False;db.commit()
    assert client.post(f'/api/v1/widgets/devices/{device.id}/power',headers=wh,json={'enabled':False,'expected_generation':None}).status_code==409
    device.owner_id=None;db.commit()
    assert client.post(f'/api/v1/widgets/devices/{device.id}/power',headers=wh,json={'enabled':False,'expected_generation':None}).status_code==404
    parent=db.get(MobileSession,decode_token(login['access_token'])['sid']);parent.expires_at=datetime.now(timezone.utc)-timedelta(seconds=1);db.commit()
    assert client.get('/api/v1/widgets/devices',headers=wh).status_code==401


def test_delayed_widget_intent_cannot_control_new_generation(client,db,monkeypatch):
    from app.models.device_lifecycle import DeviceIdentity
    from app.services.mqtt_service import mqtt_service
    user,login,headers,widget=credentials(client,db)
    device=Device(serial_number='REASSIGNED',secret_hash='unused',owner_id=user.id,lifecycle_status='ACTIVE',is_online=True)
    db.add(device);db.flush();identity=DeviceIdentity(device_id=device.id,generation=1,protocol_version=1);db.add(identity);db.commit()
    wh={'Authorization':'Bearer '+widget['token']}
    old=client.get('/api/v1/widgets/devices',headers=wh).json()['devices'][0]
    identity.generation=2;db.commit()
    messages=[]
    monkeypatch.setattr(mqtt_service,'publish_command',lambda *args,**kwargs:(messages.append(args) or True))
    response=client.post(f'/api/v1/widgets/devices/{device.id}/power',headers=wh,json={'enabled':True,'expected_generation':old.get('generation')})
    assert response.status_code==409
    assert not messages
