import base64
from pathlib import Path
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from app.core.config import settings

def signing_key():
    if not settings.device_signing_key_file:
        raise HTTPException(503, 'Configure DEVICE_SIGNING_KEY_FILE before provisioning devices.')
    try:
        key = serialization.load_pem_private_key(Path(settings.device_signing_key_file).read_bytes(), password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
            raise ValueError('Expected P-256 key')
        return key
    except (OSError, ValueError, TypeError):
        raise HTTPException(503, 'Device signing key is unavailable or invalid.')

def public_pem(key):
    return key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()

def private_pem(key):
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()

def sign_body(body: str) -> dict:
    signature = signing_key().sign(body.encode(), ec.ECDSA(hashes.SHA256()))
    return {'body': body, 'signature': base64.b64encode(signature).decode()}
