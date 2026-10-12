import base64,json,secrets,hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag
from fastapi import HTTPException
from app.models.device_provisioning import DeviceProvisioning
from app.services.device_authorization import signing_key

def cipher():
    key=signing_key().private_numbers().private_value.to_bytes(32,'big')
    return AESGCM(hashlib.sha256(b'Lily provisioning archive v1\0'+key).digest())

def archive_config(db,device_id,data):
    nonce=secrets.token_bytes(12)
    encrypted=nonce+cipher().encrypt(nonce,json.dumps(data).encode(),str(device_id).encode())
    db.add(DeviceProvisioning(device_id=device_id,encrypted_config=base64.b64encode(encrypted).decode()))

def stored_config(db,device_id):
    row=db.get(DeviceProvisioning,device_id)
    if not row:raise HTTPException(409,'Credentials were not retained for this older device. Use the configuration file saved when it was created; a hashed secret cannot be recovered.')
    try:
        raw=base64.b64decode(row.encrypted_config,validate=True)
        return json.loads(cipher().decrypt(raw[:12],raw[12:],str(device_id).encode()))
    except (ValueError,InvalidTag):raise HTTPException(503,'Stored configuration cannot be decrypted. Restore the original device signing key.')
