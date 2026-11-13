"""Compile approved Lily targets in an isolated directory using archived credentials."""

import base64
import hashlib
import json
from pathlib import Path
import secrets
import shutil
import subprocess
from tempfile import TemporaryDirectory
from threading import Lock

from fastapi import HTTPException

from app.core.config import settings
from app.services.provisioning_archive import cipher


FLASH_SIZE = 16 * 1024 * 1024
TARGETS = {
    'lily_led_strip': ('esp32_test_light', 'led_strip', 0x330000),
    'lily_v2': ('esp32_device', 'lily_v2', 0x300000),
}
_build_lock = Lock()


def require_builder():
    root = Path(settings.firmware_source_dir or '')
    if not settings.firmware_source_dir or not (root / 'firmware_shared' / 'library.json').is_file():
        raise HTTPException(503, 'This server has no Lily firmware build environment configured.')
    return root


def encode_segment(address, data):
    return {'address': address, 'data_base64': base64.b64encode(data).decode('ascii'),
            'sha256': hashlib.sha256(data).hexdigest()}


def build_package(model_key, serial, header, *, factory, partition_sha256=None):
    source = require_builder()
    project_name, environment, max_app_size = TARGETS[model_key]
    if not _build_lock.acquire(blocking=False):
        raise HTTPException(503, 'A Lily firmware build is running. Try again when it finishes.')
    try:
        with TemporaryDirectory(prefix='lily-firmware-') as temporary:
            root = Path(temporary)
            project = root / project_name
            shutil.copytree(source / 'firmware_shared', root / 'firmware_shared',
                            ignore=shutil.ignore_patterns('.pio', 'tests', '*.local.h'))
            shutil.copytree(source / project_name, project, ignore=shutil.ignore_patterns(
                '.pio', 'device_config*.h', '__pycache__', 'data'))
            (project / 'include').mkdir(exist_ok=True)
            (project / 'include' / 'device_config.h').write_text(header, encoding='utf-8')
            command = [settings.firmware_pio, 'run', '-d', str(project), '-e', environment]
            # Compiler diagnostics may contain lines from the secret header.
            subprocess.run(command, check=True, timeout=600, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            build = project / '.pio' / 'build' / environment
            partitions = (build / 'partitions.bin').read_bytes()
            if len(partitions) != 0xc00:
                raise ValueError('Unexpected partition image size')
            partition_digest = hashlib.sha256(partitions.ljust(0x1000, b'\xff')).hexdigest()
            if not factory and partition_sha256 != partition_digest:
                raise HTTPException(409, 'The board partition layout does not match this firmware. No firmware was written.')
            app = (build / 'firmware.bin').read_bytes()
            if len(app) > max_app_size or serial.encode('ascii') + b'\0' not in app:
                raise ValueError('Firmware identity or size failed validation')
            segments = [encode_segment(0x10000, app)]
            if factory:
                bootloader = (build / 'bootloader.bin').read_bytes()
                if bootloader[0] != 0xe9 or bootloader[2] != 2 or len(bootloader) > 0x8000:
                    raise ValueError('Expected a DIO bootloader for the supported ESP32-S3')
                # Erased OTA metadata selects app0. Keep NVS and other regions erased.
                segments = [encode_segment(0, bootloader), encode_segment(0x8000, partitions), *segments]
                if model_key == 'lily_v2':
                    (project / 'data').mkdir()
                    (project / 'data' / '.keep').touch()
                    subprocess.run([*command, '-t', 'buildfs'], check=True, timeout=120,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    filesystem = (build / 'littlefs.bin').read_bytes()
                    if len(filesystem) != 0x9e0000:
                        raise ValueError('Unexpected factory LittleFS size')
                    segments.append(encode_segment(0x610000, filesystem))
            return {'serial_number': serial, 'model_key': model_key, 'chip': 'ESP32-S3',
                    'flash_size': FLASH_SIZE, 'partition_sha256': partition_digest, 'segments': segments}
    except (OSError, ValueError, subprocess.SubprocessError):
        raise HTTPException(503, 'The server could not build the Lily firmware package. Check the PlatformIO installation.') from None
    finally:
        _build_lock.release()


def seal_package(mac, package):
    nonce = secrets.token_bytes(12)
    return nonce + cipher().encrypt(nonce, json.dumps(package).encode(), f'usb:{mac}'.encode())


def open_package(mac, encrypted):
    from cryptography.exceptions import InvalidTag

    try:
        return json.loads(cipher().decrypt(encrypted[:12], encrypted[12:], f'usb:{mac}'.encode()))
    except (ValueError, InvalidTag):
        raise HTTPException(503, 'The saved firmware package cannot be decrypted. Restore the device signing key.') from None
