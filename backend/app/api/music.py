import hashlib
import os
from pathlib import Path
from uuid import uuid4

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    UploadFile,
)
from fastapi.responses import FileResponse
from sqlalchemy import select, or_
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.core.config import settings
from app.db.session import get_db
from app.models.music import Music
from app.models.user import User
from app.schemas.admin import EnabledUpdate

router = APIRouter(prefix="/music", tags=["music"])


def serialize_track(track):
    return {'id': track.id, 'title': track.title, 'description': track.description,
            'filename': track.filename, 'filesize': track.filesize,
            'checksum_sha256': track.checksum_sha256, 'is_private': track.owner_id is not None}


@router.post('/private')
async def upload_private_music(file: UploadFile = File(...),
                               user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    filename = (file.filename or '').replace('\\', '/').split('/')[-1][:255]
    if not filename.lower().endswith('.mp3'):
        raise HTTPException(400, 'Only MP3 files are accepted')
    limit = settings.max_music_size_mb * 1024 * 1024
    if file.size is not None and file.size > limit:
        raise HTTPException(413, f'File exceeds {settings.max_music_size_mb} MB')
    directory = Path(settings.music_dir)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (uuid4().hex + '.mp3')
    digest = hashlib.sha256()
    total = 0
    try:
        with path.open('xb') as target:
            while chunk := await file.read(64 * 1024):
                if total == 0 and not (chunk.startswith(b'ID3') or
                        (len(chunk) >= 2 and chunk[0] == 255 and chunk[1] & 224 == 224)):
                    raise HTTPException(422, 'The selected file does not have an MP3 header')
                total += len(chunk)
                if total > limit:
                    raise HTTPException(413, f'File exceeds {settings.max_music_size_mb} MB')
                digest.update(chunk)
                target.write(chunk)
        if total == 0:
            raise HTTPException(422, 'The selected MP3 is empty')
        track = Music(owner_id=user.id, title=Path(filename).stem[:200] or 'Audio',
                      filename=filename, storage_path=str(path), filesize=total,
                      checksum_sha256=digest.hexdigest(), enabled=True)
        db.add(track); db.commit(); db.refresh(track)
        return serialize_track(track)
    except BaseException:
        db.rollback()
        path.unlink(missing_ok=True)
        raise
    finally:
        await file.close()


@router.get('/{music_id}/device.mp3')
def device_media(music_id: int, token: str, db: Session = Depends(get_db)):
    from app.core.security import decode_token
    from app.models.device import Device
    from app.api.device_operations import device_generation
    from app.services.device_features import require_features
    try:
        claims = decode_token(token)
        if claims.get('type') != 'device_media' or claims.get('music_id') != music_id:
            raise ValueError()
        device = db.get(Device, int(claims['sub']))
        if (not device or device.lifecycle_status != 'ACTIVE' or device.owner_id is None
                or device.owner_id != claims.get('owner')
                or device_generation(db, device) != claims.get('generation')):
            raise ValueError()
    except Exception:
        raise HTTPException(403, 'Invalid or expired device media authorization')
    require_features(db, device, 'audio')
    track = db.get(Music, music_id)
    if not track or not track.enabled or (track.owner_id is not None and track.owner_id != device.owner_id):
        raise HTTPException(404, 'Music not found')
    if not Path(track.storage_path).is_file():
        raise HTTPException(410, 'Music file missing from storage')
    return FileResponse(track.storage_path, media_type='audio/mpeg',
                        headers={'Cache-Control': 'private, no-store'})

@router.get("")
def list_music(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    tracks = db.scalars(
        select(Music)
        .where(Music.enabled == True, or_(Music.owner_id.is_(None), Music.owner_id == user.id))
        .order_by(Music.title)
    ).all()

    return [serialize_track(track) for track in tracks]

@router.get("/{music_id}/download")
def download_music(
    music_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    music = db.get(Music, music_id)

    if not music or not music.enabled or (music.owner_id is not None and music.owner_id != user.id):
        raise HTTPException(
            status_code=404,
            detail="Music not found",
        )

    if not os.path.exists(music.storage_path):
        raise HTTPException(
            status_code=410,
            detail="Music file missing from storage",
        )

    return FileResponse(
        music.storage_path,
        media_type="audio/mpeg",
        filename=music.filename,
    )

@router.post("/admin/upload")
async def upload_music(
    title: str = Form(...),
    description: str | None = Form(None),
    file: UploadFile = File(...),
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    if not file.filename or not file.filename.lower().endswith(".mp3"):
        raise HTTPException(
            status_code=400,
            detail="Only MP3 files are accepted",
        )

    data = await file.read()
    max_bytes = settings.max_music_size_mb * 1024 * 1024

    if len(data) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds {settings.max_music_size_mb} MB",
        )

    Path(settings.music_dir).mkdir(
        parents=True,
        exist_ok=True,
    )

    stored_name = f"{uuid4().hex}.mp3"
    stored_path = os.path.join(
        settings.music_dir,
        stored_name,
    )

    with open(stored_path, "wb") as output:
        output.write(data)

    checksum = hashlib.sha256(data).hexdigest()

    music = Music(
        title=title,
        description=description,
        filename=file.filename,
        storage_path=stored_path,
        filesize=len(data),
        checksum_sha256=checksum,
        enabled=True,
    )

    db.add(music)
    db.commit()
    db.refresh(music)

    return {
        "id": music.id,
        "title": music.title,
        "filename": music.filename,
        "filesize": music.filesize,
        "checksum_sha256": checksum,
    }


@router.get("/admin/all")
def admin_list_music(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    tracks = db.scalars(select(Music).where(Music.owner_id.is_(None)).order_by(Music.created_at.desc())).all()
    return [
        {
            "id": track.id,
            "title": track.title,
            "description": track.description,
            "filename": track.filename,
            "filesize": track.filesize,
            "checksum_sha256": track.checksum_sha256,
            "enabled": track.enabled,
            "created_at": track.created_at,
        }
        for track in tracks
    ]

@router.patch("/admin/{music_id}/enabled")
def admin_set_music_enabled(
    music_id: int,
    payload: EnabledUpdate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    music = db.get(Music, music_id)
    if not music or music.owner_id is not None:
        raise HTTPException(status_code=404, detail="Music not found")

    music.enabled = payload.enabled
    db.commit()
    return {"id": music.id, "enabled": music.enabled}

@router.delete("/admin/{music_id}")
def admin_delete_music(
    music_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    music = db.get(Music, music_id)
    if not music or music.owner_id is not None:
        raise HTTPException(status_code=404, detail="Music not found")

    path = music.storage_path
    db.delete(music)
    db.commit()

    if path and os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass

    return {"ok": True}
