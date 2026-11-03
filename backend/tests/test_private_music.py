import hashlib
from sqlalchemy import select, create_engine, inspect, text
from app.models.music import Music
from app.models.user import User
from app.services.access_sessions import issue_session
from app.services.permission_catalog import MOBILE_PERMISSIONS
from test_device_features import model_device


def other_user(db):
    u = User(email='other@music.test', password_hash='unused', is_active=True)
    db.add(u); db.commit()
    return {'Authorization': 'Bearer '+issue_session(db,u,permissions=MOBILE_PERMISSIONS)['access_token']}


def upload(client, headers, data=b'ID3-private-mp3', name='Rain.mp3'):
    return client.post('/api/v1/music/private',headers=headers,
                       files={'file': (name,data,'audio/mpeg')})


def test_private_upload_is_owner_scoped(client, db, owner, admin, tmp_path, monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings,'music_dir',str(tmp_path))
    result=upload(client,owner[1]); assert result.status_code == 200
    track=result.json(); ident=track['id']
    assert track['is_private'] is True
    assert track['checksum_sha256']==hashlib.sha256(b'ID3-private-mp3').hexdigest()
    assert client.get('/api/v1/music',headers=owner[1]).json()[0]['id']==ident
    assert client.get(f'/api/v1/music/{ident}/download',headers=owner[1]).content==b'ID3-private-mp3'
    other=other_user(db)
    assert client.get('/api/v1/music',headers=other).json()==[]
    assert client.get(f'/api/v1/music/{ident}/download',headers=other).status_code==404
    assert client.get('/api/v1/music/admin/all',headers=admin).json()==[]
    assert client.patch(f'/api/v1/music/admin/{ident}/enabled',headers=admin,json={'enabled':False}).status_code==404
    assert client.delete(f'/api/v1/music/admin/{ident}',headers=admin).status_code==404


def test_upload_validation_and_cleanup(client,db,owner,tmp_path,monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings,'music_dir',str(tmp_path))
    monkeypatch.setattr(settings,'max_music_size_mb',1)
    for data,name,status in [(b'', 'empty.mp3',422),(b'fake','fake.mp3',422),
                              (b'ID3-song','song.wav',400),(b'ID3'+b'x'*1048576,'big.mp3',413)]:
        assert upload(client,owner[1],data,name).status_code==status
    assert list(tmp_path.iterdir())==[]
    assert list(db.scalars(select(Music)))==[]


def test_private_playback_and_device_token(client,db,owner,admin,tmp_path,monkeypatch):
    from app.core.config import settings
    from app.services.audio_catalog import media_token
    monkeypatch.setattr(settings,'music_dir',str(tmp_path))
    ident=upload(client,owner[1]).json()['id']
    device,_=model_device(db,owner,['audio']); device.firmware_version='2.0.0';db.commit()
    from app.services.mqtt_service import mqtt_service
    sent=[]
    monkeypatch.setattr(mqtt_service,'publish_command',lambda serial,command,**kw: sent.append(command) or True)
    base=f'/api/v1/devices/{device.id}/audio/catalog'
    assert client.post(base,headers=admin,json={'music_id':ident}).status_code==404
    assert client.post(base,headers=owner[1],json={'music_id':ident}).status_code==200
    assert client.get(sent[-1]['payload']['path']).content==b'ID3-private-mp3'
    stranger=User(email='stranger@device.test',password_hash='unused',is_active=True)
    db.add(stranger);db.flush(); device.owner_id=stranger.id;db.commit()
    # Even a freshly signed capability for another device owner cannot expose the private track.
    from app.api.device_operations import device_generation
    token=media_token(device,device_generation(db,device),ident)
    assert client.get(f'/api/v1/music/{ident}/device.mp3?token={token}').status_code==404


def test_private_music_migration_preserves_shared_tracks(tmp_path):
    from alembic.config import Config
    from alembic import command
    from pathlib import Path
    engine=create_engine('sqlite:///'+str(tmp_path/'old.db'))
    root=Path(__file__).resolve().parents[1]
    config=Config(str(root/'alembic.ini'));config.set_main_option('script_location',str(root/'migrations'))
    with engine.begin() as conn:
        config.attributes['connection']=conn
        command.upgrade(config,'20261019_rbac')
        conn.execute(text("INSERT INTO music (title,filename,storage_path,filesize,checksum_sha256,enabled,created_at) VALUES ('Shared','shared.mp3','/old.mp3',3,'abc',1,CURRENT_TIMESTAMP)"))
        command.upgrade(config,'head')
        assert 'owner_id' in {c['name'] for c in inspect(conn).get_columns('music')}
        assert conn.execute(text('SELECT title,owner_id FROM music')).one()==('Shared',None)


def test_failed_database_commit_removes_uploaded_file(client,db,owner,tmp_path,monkeypatch):
    import pytest
    from app.core.config import settings
    monkeypatch.setattr(settings,'music_dir',str(tmp_path))
    def fail_commit(): raise RuntimeError('database unavailable')
    monkeypatch.setattr(db,'commit',fail_commit)
    with pytest.raises(RuntimeError,match='database unavailable'):
        upload(client,owner[1])
    assert list(tmp_path.iterdir())==[]
    assert list(db.scalars(select(Music)))==[]
