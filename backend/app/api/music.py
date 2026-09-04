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
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.core.config import settings
from app.db.session import get_db
from app.models.music import Music
from app.models.user import User
from app.schemas.admin import EnabledUpdate

router = APIRouter(prefix="/music", tags=["music"])

@router.get("")
def list_music(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    tracks = db.scalars(
        select(Music)
        .where(Music.enabled == True)
        .order_by(Music.title)
    ).all()

    return [
        {
            "id": track.id,
            "title": track.title,
            "description": track.description,
            "filename": track.filename,
            "filesize": track.filesize,
            "checksum_sha256": track.checksum_sha256,
        }
        for track in tracks
    ]

@router.get("/{music_id}/download")
def download_music(
    music_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    music = db.get(Music, music_id)

    if not music or not music.enabled:
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
    tracks = db.scalars(select(Music).order_by(Music.created_at.desc())).all()
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
    if not music:
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
    if not music:
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
