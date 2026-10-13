import hashlib,hmac
from datetime import datetime,timezone
from fastapi import APIRouter,Depends,HTTPException
from pydantic import BaseModel,Field
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.api.deps import bearer,get_current_user
from fastapi.security import HTTPAuthorizationCredentials
from app.db.session import get_db
from app.core.security import decode_token
from app.core.config import settings
from app.models.user import User
from app.models.device import Device
from app.models.device_lifecycle import MobileSession
from app.models.device_provisioning import WidgetCredential
from app.services.mobile_sessions import utc
from app.api.devices import serialize_device
from app.api.device_operations import locked_device,device_generation,require_mutable
from app.services.mqtt_service import mqtt_service

router=APIRouter(prefix='/widgets',tags=['home-screen widgets'])
class Installation(BaseModel):
    installation_id:str=Field(pattern=r'^[a-f0-9]{32}$')
class Power(BaseModel):
    enabled:bool=Field(strict=True)
    expected_generation:int | None=Field(..., strict=True, ge=0)

def active_parent(db,session_id):
    row=db.scalar(select(MobileSession).where(MobileSession.id==session_id).with_for_update().execution_options(populate_existing=True))
    if not row or row.revoked_at or utc(row.expires_at)<=datetime.now(timezone.utc):raise HTTPException(401,'Widget session expired. Open Lily and sign in.')
    user=db.get(User,row.user_id)
    if not user or not user.is_active:raise HTTPException(401,'Inactive account')
    return row,user

@router.post('/session')
def issue_widget(payload:Installation,user:User=Depends(get_current_user),creds:HTTPAuthorizationCredentials=Depends(bearer),db:Session=Depends(get_db)):
    sid=decode_token(creds.credentials).get('sid')
    if not sid:raise HTTPException(409,'Sign in again to enable home-screen widgets.')
    parent,current=active_parent(db,sid)
    if current.id!=user.id:raise HTTPException(401,'Invalid session')
    token='lily_widget_'+hmac.new(settings.secret_key.encode(),('widget-v1|'+sid+'|'+payload.installation_id).encode(),hashlib.sha256).hexdigest()
    digest=hashlib.sha256(token.encode()).hexdigest()
    if not db.get(WidgetCredential,digest):db.add(WidgetCredential(token_hash=digest,session_id=sid,installation_id=payload.installation_id))
    db.commit()
    return {'token':token,'expires_at':utc(parent.expires_at).isoformat()}

def widget_user(creds:HTTPAuthorizationCredentials=Depends(bearer),db:Session=Depends(get_db)):
    row=db.get(WidgetCredential,hashlib.sha256(creds.credentials.encode()).hexdigest())
    if not row:raise HTTPException(401,'Invalid widget credential')
    return active_parent(db,row.session_id)[1]

def projection(db,device):
    data=serialize_device(device,db);caps=data['smart_home']['capabilities']
    light='light' in caps
    power='power' in caps
    state=data['light']['enabled'] if light else data['generic_state'].get('enabled')
    return {'id':device.id,'generation':device_generation(db,device),'name':device.name or data['smart_home']['device_type_name'] or device.model,'serial_number':device.serial_number,'status':data['status'],'online':bool(device.is_online and data['status']=='ONLINE'),'enabled':state if isinstance(state,bool) else None,'can_control':bool(power and data['status']=='ONLINE'),'supports_light':light}

def snapshot(db,user):
    return {'devices':[projection(db,d) for d in db.scalars(select(Device).where(Device.owner_id==user.id).order_by(Device.id))],'updated_at':datetime.now(timezone.utc).isoformat()}

@router.get('/devices')
def list_widget_devices(user:User=Depends(widget_user),db:Session=Depends(get_db)):
    return snapshot(db,user)

@router.post('/devices/{device_id}/power')
def widget_power(device_id:int,payload:Power,user:User=Depends(widget_user),db:Session=Depends(get_db)):
    device=locked_device(db,device_id=device_id)
    if not device or device.owner_id!=user.id:raise HTTPException(404,'Device not found')
    require_mutable(device)
    if payload.expected_generation != device_generation(db,device):
        raise HTTPException(409,'Device ownership changed. Refresh before controlling it.')
    item=projection(db,device)
    if not item['can_control']:raise HTTPException(409,'Device is offline or does not support power control')
    if item['supports_light']:
        command={'type':'light','payload':{'enabled':payload.enabled,'brightness':device.brightness,'r':device.color_r,'g':device.color_g,'b':device.color_b}}
    else:command={'type':'power','payload':{'enabled':payload.enabled}}
    delivered=mqtt_service.publish_command(device.serial_number,command,generation=device_generation(db,device))
    if not delivered:raise HTTPException(503,'Broker unavailable. Command was not sent.')
    db.commit()
    return {'mqtt_published':True,'snapshot':snapshot(db,user),'detail':'Command sent; device state updates after its next report.'}
