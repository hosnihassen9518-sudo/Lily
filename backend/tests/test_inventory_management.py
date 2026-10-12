import csv,io
from pathlib import Path
from sqlalchemy import select
from app.models.device import Device
from app.models.smart_device import DeviceType
from app.services.device_inventory import seed_models


def generate(client,db,admin,monkeypatch,tmp_path):
    from app.core.config import settings
    path=tmp_path/'persistent'/'signing.pem'
    monkeypatch.setattr(settings,'device_signing_key_file',str(path))
    seed_models(db)
    dtype=db.scalar(select(DeviceType).where(DeviceType.key=='test_light'))
    response=client.post('/api/v1/admin/device-inventory',headers=admin,json={'device_type_id':dtype.id,'model_key':'lily_test_light'})
    assert response.status_code==200,response.text
    return response.json(),path


def test_missing_key_initializes_and_credentials_are_recoverable(client,db,admin,owner,monkeypatch,tmp_path):
    data,path=generate(client,db,admin,monkeypatch,tmp_path)
    key=path.read_bytes();device_id=data['device']['id']
    assert path.stat().st_mode&0o777==0o600
    again=client.get(f'/api/v1/admin/device-inventory/{device_id}/credentials',headers=admin)
    assert again.status_code==200
    assert again.json()['device_secret']==data['device_secret']
    config=client.get(f'/api/v1/admin/device-inventory/{device_id}/config',headers=admin)
    assert config.status_code==200 and config.text==data['config_header']
    assert client.get(f'/api/v1/admin/device-inventory/{device_id}/credentials',headers=owner[1]).status_code==403
    from app.models.device_provisioning import DeviceProvisioning
    archive=db.get(DeviceProvisioning,device_id)
    assert data['device_secret'] not in archive.encrypted_config
    from app.services.device_authorization import signing_key
    signing_key();assert path.read_bytes()==key


def test_invalid_existing_key_is_never_replaced(client,db,admin,monkeypatch,tmp_path):
    from app.core.config import settings
    path=tmp_path/'bad.pem';path.write_bytes(b'broken-existing-key')
    monkeypatch.setattr(settings,'device_signing_key_file',str(path))
    seed_models(db);dtype=db.scalar(select(DeviceType).where(DeviceType.key=='test_light'))
    response=client.post('/api/v1/admin/device-inventory',headers=admin,json={'device_type_id':dtype.id,'model_key':'lily_test_light'})
    assert response.status_code==503
    assert path.read_bytes()==b'broken-existing-key'
    assert not list(db.scalars(select(Device)))


def test_selected_csv_fields_credentials_and_formula_neutralization(client,db,admin,monkeypatch,tmp_path):
    data,path=generate(client,db,admin,monkeypatch,tmp_path)
    device=db.get(Device,data['device']['id']);device.name='=HYPERLINK("bad")';db.commit()
    response=client.get('/api/v1/admin/devices/export.csv?fields=serial_number,name,device_secret',headers=admin)
    assert response.status_code==200
    rows=list(csv.reader(io.StringIO(response.text)))
    assert rows[0]==['serial_number','name','device_secret']
    assert rows[1]==[data['serial_number'],'\'=HYPERLINK("bad")',data['device_secret']]
    default=client.get('/api/v1/admin/devices/export.csv',headers=admin)
    assert 'device_secret' not in next(csv.reader(io.StringIO(default.text)))
    assert client.get('/api/v1/admin/devices/export.csv?fields=secret_hash',headers=admin).status_code==422


def test_lost_key_is_not_silently_replaced_after_provisioning(client,db,admin,monkeypatch,tmp_path):
    data,path=generate(client,db,admin,monkeypatch,tmp_path)
    original=path.read_bytes();path.unlink()
    dtype=db.scalar(select(DeviceType).where(DeviceType.key=='test_light'))
    response=client.post('/api/v1/admin/device-inventory',headers=admin,json={'device_type_id':dtype.id,'model_key':'lily_test_light'})
    assert response.status_code==503
    assert not path.exists()
    path.write_bytes(original)
    recovered=client.get(f"/api/v1/admin/device-inventory/{data['device']['id']}/credentials",headers=admin)
    assert recovered.json()['device_secret']==data['device_secret']


def test_resync_preserves_credentials_and_reports_schedule_failure(client,db,admin,monkeypatch,tmp_path):
    data,path=generate(client,db,admin,monkeypatch,tmp_path)
    device=db.get(Device,data['device']['id']);device.lifecycle_status='ACTIVE';device.is_online=True;db.commit()
    from app.services.mqtt_service import mqtt_service
    commands=[]
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda *args,**kwargs:True)
    monkeypatch.setattr(mqtt_service,'publish_command',lambda *args,**kwargs:(commands.append(args) or True))
    endpoint=f'/api/v1/admin/device-inventory/{device.id}/resync'
    assert client.post(endpoint,headers=admin).status_code==200
    assert commands[0][1]=={'type':'status_request'}
    saved=client.get(f'/api/v1/admin/device-inventory/{device.id}/credentials',headers=admin).json()
    assert saved=={'serial_number':data['serial_number'],'device_secret':data['device_secret']}
    monkeypatch.setattr(mqtt_service,'publish_schedule',lambda *args,**kwargs:False)
    assert client.post(endpoint,headers=admin).status_code==503
    assert len(commands)==1
