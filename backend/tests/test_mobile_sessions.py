from datetime import datetime, timezone, timedelta
from app.core.security import hash_password
from app.models.user import User

def test_calendar_expiry():
    from app.services.mobile_sessions import calendar_expiry
    assert calendar_expiry(datetime(2024, 1, 31, tzinfo=timezone.utc), 3) == datetime(2024, 4, 30, tzinfo=timezone.utc)
    assert calendar_expiry(datetime(2023, 11, 30, tzinfo=timezone.utc), 3) == datetime(2024, 2, 29, tzinfo=timezone.utc)

def test_mobile_refresh_logout_and_policy(client, db, admin):
    user = User(email='mobile@test.org', password_hash=hash_password('longpassword'), is_active=True)
    db.add(user); db.commit()
    response = client.post('/api/v1/auth/mobile/login', json={'email':user.email,'password':'longpassword'})
    assert response.status_code == 200
    first = response.json()
    expiry = datetime.fromisoformat(first['session_expires_at'])
    assert 89 <= (expiry - datetime.now(timezone.utc)).days <= 92
    assert client.patch('/api/v1/admin/mobile-session-policy', headers=admin, json={'months':13}).status_code == 422
    assert client.patch('/api/v1/admin/mobile-session-policy', headers=admin, json={'months':1}).json() == {'months':1}
    body = {'refresh_token':first['refresh_token'], 'request_id':'request-one'}
    second = client.post('/api/v1/auth/mobile/refresh', json=body).json()
    assert second['session_expires_at'] == first['session_expires_at']
    assert second['refresh_token'] != first['refresh_token']
    assert client.post('/api/v1/auth/mobile/refresh', json=body).json()['refresh_token'] == second['refresh_token']
    assert client.post('/api/v1/auth/mobile/refresh', json={**body,'request_id':'other-request'}).status_code == 401
    headers={'Authorization':'Bearer '+second['access_token']}
    assert client.get('/api/v1/auth/me', headers=headers).status_code == 200
    client.post('/api/v1/auth/mobile/logout', json={'refresh_token':second['refresh_token']})
    assert client.get('/api/v1/auth/me', headers=headers).status_code == 401

def test_refresh_token_cannot_authorize_and_inactive_login_fails(client, db):
    user = User(email='inactive@test.org', password_hash=hash_password('longpassword'), is_active=False)
    db.add(user); db.commit()
    assert client.post('/api/v1/auth/mobile/login', json={'email':user.email,'password':'longpassword'}).status_code == 401

def test_refresh_lost_response_during_outage_does_not_require_early_login(db):
    from app.services.mobile_sessions import issue_mobile_session,rotate_mobile_session
    user=User(email='outage@test.org',password_hash='unused',is_active=True);db.add(user);db.commit()
    now=datetime.now(timezone.utc)
    first=issue_mobile_session(db,user,now)
    second=rotate_mobile_session(db,first['refresh_token'],'outage-request',now)
    recovered=rotate_mobile_session(db,first['refresh_token'],'outage-request',now+timedelta(minutes=5))
    assert recovered['refresh_token']==second['refresh_token']
    assert recovered['session_expires_at']==first['session_expires_at']
