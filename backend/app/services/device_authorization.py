import base64, os, tempfile
from pathlib import Path
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from app.core.config import settings

def signing_key():
    if not settings.device_signing_key_file:
        raise HTTPException(503, 'Configure DEVICE_SIGNING_KEY_FILE before provisioning devices.')
    path=Path(settings.device_signing_key_file)
    try:
        key = serialization.load_pem_private_key(path.read_bytes(), password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
            raise ValueError('Expected P-256 key')
        return key
    except (OSError, ValueError, TypeError):
        raise HTTPException(503, 'Device signing key is unavailable or invalid. Check the configured persistent file and its permissions; an existing key is never replaced automatically.')

def prepare_signing_key(db):
    """Initialize only fresh installations; preserve established factory trust."""
    from sqlalchemy import select
    from sqlalchemy.exc import IntegrityError
    from app.models.device_lifecycle import AppSetting, DeviceIdentity
    from app.models.device_provisioning import DeviceProvisioning
    if not settings.device_signing_key_file:
        return signing_key()
    path = Path(settings.device_signing_key_file)
    trust = db.get(AppSetting, 'factory_signing_public_key')
    established = trust is not None or db.scalar(select(DeviceProvisioning.device_id).limit(1)) is not None or db.scalar(select(DeviceIdentity.device_id).where(DeviceIdentity.protocol_version == 1).limit(1)) is not None
    if not path.exists() and established:
        raise HTTPException(503, 'Restore the original persistent device signing key. Existing factory credentials prevent automatic replacement.')
    try:
        if not path.exists():
            path.parent.mkdir(parents=True,exist_ok=True)
            fd,temp=tempfile.mkstemp(prefix='.lily-key-',dir=path.parent)
            try:
                with os.fdopen(fd,'wb') as output:
                    output.write(private_pem(ec.generate_private_key(ec.SECP256R1())).encode());output.flush();os.fsync(output.fileno())
                try:os.link(temp,path)
                except FileExistsError:pass
            finally:os.unlink(temp)
    except OSError:
        raise HTTPException(503, 'Cannot initialize the persistent device signing key. Check directory permissions.')
    key = signing_key()
    public = public_pem(key.public_key())
    if trust is None:
        try:
            with db.begin_nested():
                db.add(AppSetting(key='factory_signing_public_key', value_json={'pem': public}))
                db.flush()
        except IntegrityError:
            pass
        db.commit()
        trust = db.get(AppSetting, 'factory_signing_public_key')
    if trust.value_json.get('pem') != public:
        raise HTTPException(503, 'The factory signing key does not match existing devices. Restore the original persistent key.')
    return key

def public_pem(key):
    return key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()

def private_pem(key):
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()

def sign_body(body: str) -> dict:
    signature = signing_key().sign(body.encode(), ec.ECDSA(hashes.SHA256()))
    return {'body': body, 'signature': base64.b64encode(signature).decode()}
