# Lily v2 audio

## Hardware and build

ESP32-S3 N16R8, five WS2812B pixels on GPIO18, MAX98357A VIN=5V,
BCLK=GPIO10, LRC=GPIO40, DIN=GPIO15, shared ground, 8-ohm 2W speaker.
Connect the speaker across the amplifier's speaker outputs.

Select factory model **Lily V2**, save its generated header as
`esp32_device/include/device_config.h`, and build explicitly:

```powershell
pio run -d esp32_device -e lily_v2
```

The v2 environment enables octal PSRAM and a 16MiB partition layout with two
3MiB application slots and 9.875MiB LittleFS. Actual file capacity is lower due
to filesystem overhead and a 64KiB reserve for configuration and schedules.
The factory header refuses to compile with the legacy environment.

Use PlatformIO's upload command, which uses the built bootloader's DIO flash
header. Do not force QIO in an external esptool command: this board's ROM failed
before application startup with that header, despite successful write verification.

## Playback

### Phone files (app 0.10.4+13)

Open an audio device and tap **Choose music**. **Choose MP3 from phone** opens
the system file picker. The selected MP3 (up to 20MiB) uploads privately to the
configured Lily server and appears in **My files**; shared tracks appear under
**Server catalog**. After upload, choose Play and Auto or Stream. Upload completion
means the file is on the server; playback begins only after a device command.
Private files can be played only on devices owned by that account. Other accounts
cannot list, download, or select them, and they are excluded from the shared admin
music catalog. Existing firmware 2.0.0 handles both sources without reflashing.

Deploy the backend before using this app update. Startup applies the
`20261103_private_music` migration, adding nullable ownership to music tracks;
existing tracks remain shared. Back up the server database before deployment.
Bluetooth audio and external receiver integration are deferred.

In the Music catalog, choose Play, then **Auto: store or stream** or
**Stream over Wi-Fi**. The server sends a catalog selection over MQTT, and
the device fetches media directly from its configured backend over Wi-Fi.
BLE is used for provisioning and management, not audio transport.

Auto stages one MP3 if current free space permits it, verifies byte length
and SHA-256, atomically replaces the previous MP3, then plays it. If the new
file cannot fit alongside the previous one, it streams instead. The previous
MP3 remains available; download failures do not replace it. A 5-minute track
at 128kbps is roughly 4.8MB. Replacement space must accommodate both files.

Device controls support play, stop, volume, confirmed local/stream source,
download status and playback errors. Use the refresh icon for fresh status.
Existing schedules operate on the locally stored MP3. A scheduled stop also
cancels an active catalog download. Streaming access expires after two hours;
select the catalog track again to issue fresh access. Streams need the server
and Wi-Fi; stored tracks play without the phone or server.

## Upgrade the existing LED-strip board

1. Deploy/restart the updated backend so the v2 model and catalog endpoints exist.
2. Change the existing device model from Lily LED Strip to Lily V2 in the portal.
   This supported upgrade retains the serial, keys and ownership.
3. Preserve the board's existing generated identity/keys in its v2 configuration.
   The ignored `esp32_device/include/device_config_v2.local.h` has been prepared
   from the existing LED-strip board. The v2 environment prefers that local header;
   remove it when building for another factory device. BLE, lifecycle and playback
   all use the same configuration. The original tracked configuration is unchanged.
4. **Before flashing, back up any required device files.** The new partition
   table moves LittleFS and can make saved Wi-Fi, schedules and lifecycle state
   unavailable. Firmware deliberately does not format a failed mount.
5. After explicitly accepting filesystem initialization, create an empty data
   directory and use `pio run -d esp32_device -e lily_v2 -t uploadfs` to initialize
   the new filesystem, then upload v2 firmware. These operations must target the
   confirmed board port. Reprovision with the existing owner's account and resync
   schedules. Do not initialize the filesystem as part of a routine firmware update.
6. Test one short MP3 in Auto mode, then explicitly stream the same track. Confirm
   speaker output, play/stop/volume, LED colors and schedules on physical hardware.

The firmware build and emulator tests do not establish that the physical speaker
works. The emulator also cannot validate ESP32 BLE pairing.

## Deploy the backend update from GitHub

From the existing Lily checkout on the server, preserve its `.env` and data volumes,
then run:

```bash
git fetch origin
git switch codex/lily-0.9-rbac
git pull --ff-only origin codex/lily-0.9-rbac
docker compose up -d --build backend
curl --fail http://127.0.0.1:6100/health
```

The update seeds Lily V2 without replacing an existing model or its selected
capabilities. It adds `POST /api/v1/devices/{device_id}/audio/catalog` and
`GET /api/v1/music/{music_id}/device.mp3`; check that both appear in the live API
documentation after rebuilding. The phone-file update also adds `POST /api/v1/music/private`
and applies the ownership migration described above.
Do not remove the existing database, music volume, signing key or MQTT data.

The physical board on COM7 has already been flashed and boot-verified as
LILY-2523AF441737C556, firmware 2.0.0, with 16MiB flash, 8MiB PSRAM and the larger
filesystem. Pair that new serial in the app. The previously paired LED-only serial
is a separate inventory identity and does not gain audio by pairing again.
After deployment and pairing, check Auto playback with a small catalog MP3 and
explicit streaming, then stop/volume, LED controls and schedules. Actual speaker
output and server-to-device transfer remain physical acceptance checks.
