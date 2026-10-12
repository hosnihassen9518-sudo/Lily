import base64, json, secrets
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, update, delete
from sqlalchemy.orm import Session
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.exceptions import InvalidSignature
from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.device import Device
from app.models.device_lifecycle import DeviceIdentity, DeviceOperation
from app.models.smart_device import DeviceProfile, DeviceState, DeviceTelemetry
from app.models.schedule import Schedule
from app.core.security import verify_password
from app.services.device_authorization import sign_body, public_pem, signing_key
from app.services.mqtt_service import mqtt_service

router=APIRouter(tags=['device operations'])

def locked_device(db,device_id=None,serial=None):
    condition=Device.id==device_id if device_id is not None else Device.serial_number==serial
    return db.scalar(select(Device).where(condition).with_for_update().execution_options(populate_existing=True))

def current_identity(db,device_id):
    return db.scalar(select(DeviceIdentity).where(DeviceIdentity.device_id==device_id).execution_options(populate_existing=True))

def device_generation(db,device):
    identity=current_identity(db,device.id)
    return identity.generation if identity and identity.protocol_version==1 else None

def cleanup_retained_operation(db,operation_id):
    with mqtt_service._cleanup_lock:
        return _cleanup_retained_operation(db,operation_id)

def _cleanup_retained_operation(db,operation_id):
    snapshot=db.get(DeviceOperation,operation_id)
    if not snapshot:return False
    device=locked_device(db,device_id=snapshot.device_id)
    op=db.scalar(select(DeviceOperation).where(DeviceOperation.id==operation_id).with_for_update().execution_options(populate_existing=True))
    if not op or not op.broker_cleanup_pending:
        db.rollback();return True
    if not device or device.owner_id is not None or device.lifecycle_status!='INVENTORY':
        db.rollback();return False
    serial=device.serial_number
    device_id=device.id
    # The pending flag prevents activation while PUBACK is awaited. Release DB
    # locks so the MQTT callback thread can process messages and acknowledgements.
    db.rollback()
    if not mqtt_service.clear_device_retained(serial):return False
    device=locked_device(db,device_id=device_id)
    op=db.scalar(select(DeviceOperation).where(DeviceOperation.id==operation_id).with_for_update().execution_options(populate_existing=True))
    if op and op.broker_cleanup_pending and device and device.owner_id is None and device.lifecycle_status=='INVENTORY':
        op.broker_cleanup_pending=0;db.commit();return True
    db.rollback();return False

class Challenge(BaseModel):
    challenge: str = Field(pattern=r'^[a-f0-9]{64}$')

class RuntimeCredentials(BaseModel):
    serial_number: str = Field(min_length=1, max_length=80)
    device_secret: str = Field(min_length=1, max_length=72)

class Registration(RuntimeCredentials):
    receipt_public_key: str = Field(max_length=1024)
    protocol_version: int = Field(ge=1, le=1)

class SignedEnvelope(BaseModel):
    body: str = Field(min_length=1,max_length=1024)
    signature: str = Field(min_length=1,max_length=256)

class Completion(BaseModel):
    receipt: SignedEnvelope

def device_auth(db,payload):
    device=locked_device(db,serial=payload.serial_number)
    if not device or not verify_password(payload.device_secret,device.secret_hash):
        raise HTTPException(401,'Invalid device credentials')
    return device

def require_mutable(device):
    if device.lifecycle_status=='RESET_PENDING':
        raise HTTPException(409,'Device reset pending')
    if device.lifecycle_status=='DISABLED':
        raise HTTPException(403,'Device disabled')

def require_cleanup_complete(db,device):
    pending=db.scalar(select(DeviceOperation.id).where(DeviceOperation.device_id==device.id,DeviceOperation.broker_cleanup_pending==1))
    if pending:
        raise HTTPException(409,'Device cleanup is waiting for the broker. Try again after connectivity returns.')

def owned(db,device_id,user):
    device=locked_device(db,device_id=device_id)
    if not device or device.owner_id!=user.id:
        raise HTTPException(404,'Device not found')
    return device

def supported(db,device):
    identity=current_identity(db,device.id)
    if not identity or identity.protocol_version!=1 or not identity.receipt_public_key:
        raise HTTPException(409,'Update and register compatible 0.8.0 firmware before managing this device.')
    return identity

def operation_result(op):
    return {'operation_id':op.id,'device_id':op.device_id,'status':op.status}

def authorization(device,identity,kind,operation_id,challenge):
    # The signed bytes are kept verbatim inside the envelope. Firmware never reserializes.
    body=json.dumps({'serial':device.serial_number,'kind':kind,'operation_id':operation_id,
                     'generation':identity.generation,'challenge':challenge},separators=(',',':'))
    return sign_body(body)

@router.post('/devices/{device_id}/wifi-session')
def wifi_session(device_id:int,payload:Challenge,user:User=Depends(get_current_user),db:Session=Depends(get_db)):
    device=owned(db,device_id,user);require_mutable(device)
    identity=supported(db,device)
    return {'authorization':authorization(device,identity,'update_wifi',secrets.token_hex(16),payload.challenge)}

@router.post('/devices/{device_id}/removal')
def remove_device(device_id:int,user:User=Depends(get_current_user),db:Session=Depends(get_db)):
    device=owned(db,device_id,user)
    if device.lifecycle_status=='RESET_PENDING':
        op=db.scalar(select(DeviceOperation).where(DeviceOperation.device_id==device.id,DeviceOperation.status=='pending'))
        if op: return operation_result(op)
        raise HTTPException(409,'Reset operation unavailable')
    require_mutable(device);identity=supported(db,device);signing_key()
    changed=db.execute(update(Device).where(Device.id==device.id,Device.owner_id==user.id,Device.lifecycle_status==device.lifecycle_status).values(lifecycle_status='RESET_PENDING'))
    if changed.rowcount!=1:
        db.rollback();raise HTTPException(409,'Device changed; reload and retry')
    op=DeviceOperation(id=secrets.token_hex(16),device_id=device.id,requested_by_id=user.id,generation=identity.generation)
    db.add(op);db.commit()
    mqtt_service.publish_command(device.serial_number,{'type':'operation_available'})
    return operation_result(op)

def user_operation(db,operation_id,user):
    op=db.get(DeviceOperation,operation_id)
    if not op or (op.requested_by_id!=user.id and not user.is_admin):
        raise HTTPException(404,'Operation not found')
    return op

@router.get('/device-operations/{operation_id}')
def progress(operation_id:str,user:User=Depends(get_current_user),db:Session=Depends(get_db)):
    return operation_result(user_operation(db,operation_id,user))

@router.post('/device-operations/{operation_id}/ble-authorization')
def reset_authorization(operation_id:str,payload:Challenge,user:User=Depends(get_current_user),db:Session=Depends(get_db)):
    op=user_operation(db,operation_id,user)
    device=db.get(Device,op.device_id);identity=supported(db,device)
    if op.status!='pending' or device.lifecycle_status!='RESET_PENDING' or identity.generation!=op.generation:
        raise HTTPException(409,'Reset is no longer pending')
    return {'authorization':authorization(device,identity,'reset',op.id,payload.challenge)}

@router.post('/device-operations/{operation_id}/completion-authorization')
def completion_authorization(operation_id:str,payload:Challenge,user:User=Depends(get_current_user),db:Session=Depends(get_db)):
    op=db.get(DeviceOperation,operation_id)
    if not op: raise HTTPException(404,'Operation not found')
    device=db.get(Device,op.device_id);identity=supported(db,device)
    if op.status!='completed' or device.owner_id is not None or identity.generation!=op.generation:
        raise HTTPException(409,'Reset completion is no longer current')
    return {'authorization':authorization(device,identity,'reset_ack',op.id,payload.challenge)}

@router.post('/device-runtime/register')
def register_identity(payload:Registration,db:Session=Depends(get_db)):
    device=device_auth(db,payload)
    try:
        key=serialization.load_pem_public_key(payload.receipt_public_key.encode())
    except (ValueError,TypeError):
        raise HTTPException(422,'Invalid device identity key')
    if not isinstance(key,ec.EllipticCurvePublicKey) or not isinstance(key.curve,ec.SECP256R1):
        raise HTTPException(422,'Expected P-256 identity key')
    canonical=public_pem(key)
    identity=db.get(DeviceIdentity,device.id)
    if not identity:
        identity=DeviceIdentity(device_id=device.id,receipt_public_key=canonical);db.add(identity)
    elif identity.receipt_public_key and identity.receipt_public_key!=canonical:
        raise HTTPException(409,'Factory receipt identity cannot be replaced')
    if device.lifecycle_status=='RESET_PENDING' and identity.protocol_version!=1:
        raise HTTPException(409,'Cannot replace identity during reset')
    identity.receipt_public_key=canonical;identity.protocol_version=1;db.commit()
    return {'generation':identity.generation,'lifecycle_status':device.lifecycle_status}

@router.post('/device-runtime/operations')
def runtime_operations(payload:RuntimeCredentials,db:Session=Depends(get_db)):
    device=device_auth(db,payload);identity=supported(db,device)
    op=db.scalar(select(DeviceOperation).where(DeviceOperation.device_id==device.id,DeviceOperation.status=='pending'))
    return {'authorization':authorization(device,identity,'reset',op.id,'remote') if op else None,
            'generation':identity.generation,'lifecycle_status':device.lifecycle_status}

@router.post('/device-runtime/reset-complete')
def reset_complete(payload:Completion,db:Session=Depends(get_db)):
    try:
        kind,serial,operation_id,generation=payload.receipt.body.split('|')
        if kind!='reset': raise ValueError()
        device=locked_device(db,serial=serial)
        op=db.scalar(select(DeviceOperation).where(DeviceOperation.id==operation_id).with_for_update().execution_options(populate_existing=True))
        if not op or not device or op.device_id!=device.id or op.generation!=int(generation): raise ValueError()
        identity=current_identity(db,device.id)
        key=serialization.load_pem_public_key(identity.receipt_public_key.encode())
        key.verify(base64.b64decode(payload.receipt.signature,validate=True),payload.receipt.body.encode(),ec.ECDSA(hashes.SHA256()))
    except (ValueError,TypeError,AttributeError,InvalidSignature):
        raise HTTPException(401,'Invalid reset completion receipt')
    if op.status=='completed': return operation_result(op)
    if device.lifecycle_status!='RESET_PENDING' or identity.generation!=op.generation:
        raise HTTPException(409,'Stale reset operation')
    for model in (Schedule,DeviceState,DeviceTelemetry):
        db.execute(delete(model).where(model.device_id==device.id))
    profile=db.get(DeviceProfile,device.id)
    if profile:
        profile.home_id=None;profile.room_id=None
        profile.metadata_json={'model_key':profile.metadata_json['model_key']} if 'model_key' in (profile.metadata_json or {}) else {}
    device.owner_id=None;device.name=None;device.activated_at=None;device.lifecycle_status='INVENTORY';device.is_online=False
    device.light_on=False;device.audio_playing=False;device.audio_loaded=False
    device.brightness=100;device.color_r=255;device.color_g=255;device.color_b=255;device.volume=50
    device.wifi_rssi=None
    op.status='completed';op.completed_at=datetime.now(timezone.utc);op.broker_cleanup_pending=1
    db.commit()
    mqtt_service._cleanup_wake.set()
    return operation_result(op)
