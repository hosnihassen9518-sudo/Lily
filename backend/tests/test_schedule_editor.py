from test_device_features import model_device

def test_edit_schedule_and_retry_delivery(client, db, owner, admin, monkeypatch):
    from app.services.mqtt_service import mqtt_service
    from app.services.feature_schedule_sync import pending_key
    from app.models.device_lifecycle import AppSetting
    device, _ = model_device(db, owner, ['power', 'light'])
    monkeypatch.setattr(mqtt_service, 'publish_schedule', lambda *args, **kwargs: False)
    body = dict(name='Bedtime', time_of_day='20:00:00', days_of_week=[0,2,4], action={'light': {'enabled': True}})
    response = client.post(f'/api/v1/schedules/device/{device.id}', headers=owner[1], json=body)
    assert response.status_code == 200
    assert db.get(AppSetting, pending_key(device)) is not None
    sid = response.json()['id']
    response = client.patch(f'/api/v1/schedules/{sid}', headers=owner[1], json={**body, 'name': 'Morning', 'enabled': False})
    assert response.status_code == 200
    assert response.json()['name'] == 'Morning'
    assert response.json()['enabled'] is False
    assert client.patch(f'/api/v1/schedules/{sid}', headers=owner[1], json={**body, 'days_of_week': []}).status_code == 422
    sent = []
    monkeypatch.setattr(mqtt_service, 'publish_schedule', lambda serial, payload, **kw: sent.append(payload) or True)
    from app.services.feature_schedule_sync import flush_pending
    assert flush_pending(db, device)
    assert sent[-1]['schedules'] == []
    db.commit()
    assert db.get(AppSetting, pending_key(device)) is None
    response = client.patch(f'/api/v1/schedules/{sid}', headers=owner[1], json={**body, 'enabled': True})
    assert response.status_code == 200
    assert sent[-1]['timezone'] == 'Europe/Paris'
    assert sent[-1]['schedules'][0]['days'] == [0,2,4]
    assert sent[-1]['schedules'][0]['time'] == '20:00'
    assert sent[-1]['schedules'][0]['action']['light']['enabled'] is True
    assert client.patch(f'/api/v1/schedules/{sid}', headers=admin, json=body).status_code == 404
    assert client.delete(f'/api/v1/schedules/{sid}', headers=owner[1]).status_code == 200
    assert sent[-1]['schedules'] == []


def test_firmware_schedule_clock_keeps_paris_timezone():
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    for target in ('esp32_device', 'esp32_test_light'):
        source = (root / target / 'src/main.cpp').read_text()
        assert 'configTime(0' not in source, f'{target} resets the schedule timezone to UTC'
        assert 'configTzTime("CET-1CEST,M3.5.0,M10.5.0/3"' in source
        assert 'mqtt.subscribe(topic("schedule").c_str(), 1)' in source
        assert 'executeSchedulesIfDue();' in source
