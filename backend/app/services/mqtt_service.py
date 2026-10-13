import json
import logging
from threading import Event, Thread, RLock
from datetime import datetime, timezone

import paho.mqtt.client as mqtt
from sqlalchemy import select

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.device import Device
from app.models.smart_device import DeviceState, DeviceTelemetry


class MQTTService:
    def __init__(self):
        self.started = False
        self._cleanup_lock=RLock()
        self._cleanup_stop=Event()
        self._cleanup_wake=Event()
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id="lily-backend",
        )

        if settings.mqtt_username:
            self.client.username_pw_set(settings.mqtt_username, settings.mqtt_password)

        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message

    def start(self):
        if not settings.mqtt_enabled:
            print("MQTT disabled. Set MQTT_ENABLED=true in .env when broker is ready.")
            return
        self.client.connect_async(settings.mqtt_host, settings.mqtt_port, keepalive=60)
        self.client.loop_start()
        self.started = True
        self._cleanup_stop.clear()
        Thread(target=self._cleanup_loop,daemon=True).start()

    def stop(self):
        if self.started:
            self._cleanup_stop.set();self._cleanup_wake.set()
            self.client.loop_stop()
            self.client.disconnect()
            self.started = False

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        print(f"MQTT connected: {reason_code}")
        self._cleanup_wake.set()
        # V0.4 topics remain supported.
        for topic in (
            "devices/+/status", "devices/+/heartbeat", "devices/+/state", "devices/+/telemetry",
            "homes/+/devices/+/status", "homes/+/devices/+/heartbeat", "homes/+/devices/+/state", "homes/+/devices/+/telemetry",
        ):
            client.subscribe(topic,qos=1)

    def _cleanup_loop(self):
        while not self._cleanup_stop.is_set():
            try:self.retry_pending_cleanup()
            except Exception:logging.exception('Retained cleanup retry failed')
            self._cleanup_wake.wait(15);self._cleanup_wake.clear()

    def retry_pending_cleanup(self):
        if not self.client.is_connected():return
        from app.models.device_lifecycle import DeviceOperation
        from app.api.device_operations import cleanup_retained_operation
        with SessionLocal() as db:
            ids=list(db.scalars(select(DeviceOperation.id).where(DeviceOperation.broker_cleanup_pending==1)))
            for operation_id in ids:cleanup_retained_operation(db,operation_id)
            from app.models.device_lifecycle import AppSetting
            from app.services.feature_schedule_sync import flush_pending
            pending = list(db.scalars(select(AppSetting).where(AppSetting.key.like('device_schedule_features:%'))))
            for marker in pending:
                device_id = (marker.value_json or {}).get('device_id')
                device = db.scalar(select(Device).where(Device.id == device_id).with_for_update())
                if device is None: db.delete(marker)
                else: flush_pending(db, device)
            db.commit()

    def _get_device(self, db, serial: str):
        return db.scalar(select(Device).where(Device.serial_number == serial).with_for_update().execution_options(populate_existing=True))

    @staticmethod
    def _topic_identity(topic: str):
        parts = topic.split("/")
        if len(parts) == 3 and parts[0] == "devices":
            return parts[1], parts[2]
        if len(parts) == 5 and parts[0] == "homes" and parts[2] == "devices":
            return parts[3], parts[4]
        return None, None

    @staticmethod
    def _telemetry_row(device_id: int, metric: str, value, now: datetime):
        numeric = None
        text = None
        if isinstance(value, bool):
            text = str(value).lower()
        elif isinstance(value, (int, float)):
            numeric = float(value)
        elif value is not None and not isinstance(value, (dict, list)):
            text = str(value)
        else:
            text = json.dumps(value) if value is not None else None
        return DeviceTelemetry(
            device_id=device_id,
            metric=metric,
            numeric_value=numeric,
            text_value=text,
            recorded_at=now,
        )

    def _on_message(self, client, userdata, msg):
        serial, event = self._topic_identity(msg.topic)
        if not serial:
            return
        try:
            payload = json.loads(msg.payload.decode() or "{}")
        except Exception:
            return

        if not isinstance(payload,dict):return
        now = datetime.now(timezone.utc)
        with SessionLocal() as db:
            device = self._get_device(db, serial)
            if not device:
                return

            from app.models.device_lifecycle import DeviceIdentity
            identity=db.get(DeviceIdentity,device.id)
            if identity and identity.protocol_version==1 and (type(payload.get("generation")) is not int or payload["generation"]!=identity.generation):
                return
            if device.lifecycle_status in ("RESET_PENDING", "INVENTORY"):
                return

            was_online = device.is_online

            if event == "status":
                online = payload.get("status") == "online"
                device.is_online = online
                device.last_seen = now
                if online:
                    device.last_connected_at = now
                else:
                    device.last_disconnected_at = now

            elif event == "heartbeat":
                device.is_online = True
                device.last_seen = now
                device.wifi_rssi = payload.get("wifi_rssi")
                device.free_heap = payload.get("free_heap")
                device.free_storage = payload.get("free_storage")
                device.firmware_version = payload.get("firmware", device.firmware_version)

            elif event == "state":
                device.last_seen = now
                state = db.get(DeviceState, device.id)
                if not state:
                    state = DeviceState(device_id=device.id)
                    db.add(state)
                state.state = payload
                state.updated_at = now

                # Preserve V0.4 projections used by the current mobile UI.
                light = payload.get("light", {}) if isinstance(payload, dict) else {}
                audio = payload.get("audio", {}) if isinstance(payload, dict) else {}
                if light:
                    device.light_on = light.get("enabled", device.light_on)
                    device.brightness = light.get("brightness", device.brightness)
                    device.color_r = light.get("r", device.color_r)
                    device.color_g = light.get("g", device.color_g)
                    device.color_b = light.get("b", device.color_b)
                if audio:
                    device.audio_loaded = audio.get("loaded", device.audio_loaded)
                    device.audio_playing = audio.get("playing", device.audio_playing)
                    device.volume = audio.get("volume", device.volume)

            elif event == "telemetry" and isinstance(payload, dict):
                device.last_seen = now
                for metric, value in payload.items():
                    db.add(self._telemetry_row(device.id, metric, value, now))

            if event in ('status', 'heartbeat') and device.is_online and device.lifecycle_status != 'DISABLED':
                from app.services.feature_schedule_sync import flush_pending
                flush_pending(db, device, force=event == 'status' or not was_online)
            db.commit()

    def publish_command(self, serial: str, payload: dict, generation=None):
        if generation is not None: payload={**payload,"generation":generation}
        if not self.started:
            return False
        result = self.client.publish(
            f"devices/{serial}/command", json.dumps(payload), qos=1, retain=False
        )
        return result.rc == mqtt.MQTT_ERR_SUCCESS

    def publish_schedule(self, serial: str, payload: dict, generation=None):
        if generation is not None: payload={**payload,"generation":generation}
        if not self.started:
            return False
        result = self.client.publish(
            f"devices/{serial}/schedule", json.dumps(payload), qos=1, retain=True
        )
        return result.rc == mqtt.MQTT_ERR_SUCCESS

    def clear_device_retained(self, serial: str):
        if not self.started or not self.client.is_connected():
            return False
        ok=True
        for suffix in ('schedule','state','status'):
            result=self.client.publish(f'devices/{serial}/{suffix}',b'',qos=1,retain=True)
            if result.rc!=mqtt.MQTT_ERR_SUCCESS:
                ok=False;continue
            try:
                result.wait_for_publish(timeout=2)
                ok=ok and result.is_published()
            except (RuntimeError,ValueError):
                ok=False
        return ok


mqtt_service = MQTTService()
