import json
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

    def stop(self):
        if self.started:
            self.client.loop_stop()
            self.client.disconnect()
            self.started = False

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        print(f"MQTT connected: {reason_code}")
        # V0.4 topics remain supported.
        for topic in (
            "devices/+/status",
            "devices/+/heartbeat",
            "devices/+/state",
            "devices/+/telemetry",
            # V0.5 canonical smart-home topics for future firmware.
            "homes/+/devices/+/status",
            "homes/+/devices/+/heartbeat",
            "homes/+/devices/+/state",
            "homes/+/devices/+/telemetry",
        ):
            client.subscribe(topic, qos=1)

    def _get_device(self, db, serial: str):
        return db.scalar(select(Device).where(Device.serial_number == serial))

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

        now = datetime.now(timezone.utc)
        with SessionLocal() as db:
            device = self._get_device(db, serial)
            if not device:
                return

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

            db.commit()

    def publish_command(self, serial: str, payload: dict):
        if not self.started:
            return False
        result = self.client.publish(
            f"devices/{serial}/command", json.dumps(payload), qos=1, retain=False
        )
        return result.rc == mqtt.MQTT_ERR_SUCCESS

    def publish_schedule(self, serial: str, payload: dict):
        if not self.started:
            return False
        result = self.client.publish(
            f"devices/{serial}/schedule", json.dumps(payload), qos=1, retain=True
        )
        return result.rc == mqtt.MQTT_ERR_SUCCESS


mqtt_service = MQTTService()
