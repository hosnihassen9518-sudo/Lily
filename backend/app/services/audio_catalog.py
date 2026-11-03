"""Short-lived, device-scoped catalog capabilities for ESP32 Wi-Fi playback."""
from datetime import datetime, timedelta, timezone
from jose import jwt
from app.core.config import settings
from app.core.security import ALGORITHM


def media_token(device, generation, music_id):
    return jwt.encode({
        'type': 'device_media', 'sub': str(device.id), 'owner': device.owner_id,
        'generation': generation, 'music_id': music_id,
        'exp': datetime.now(timezone.utc) + timedelta(hours=2),
    }, settings.secret_key, algorithm=ALGORITHM)
