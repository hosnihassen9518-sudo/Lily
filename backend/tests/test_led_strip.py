from app.models.device_lifecycle import DeviceModel
from app.services.device_inventory import seed_models, create_inventory
from app.services.device_features import model_capabilities


def test_strip_model_has_color_controls_without_changing_test_light(db):
    seed_models(db)
    strip = db.get(DeviceModel, "lily_led_strip")
    assert strip is not None, "Missing five-pixel strip model"
    assert set(model_capabilities(db, strip)) == {"power", "light", "brightness", "rgb"}
    assert db.get(DeviceModel, "lily_test_light").capabilities is None
    seed_models(db)
    assert db.get(DeviceModel, "lily_led_strip").firmware_target == "esp32_test_light"


def test_strip_inventory_header_selects_gpio18_and_five_pixels(db):
    seed_models(db)
    model = db.get(DeviceModel, "lily_led_strip")
    assert model is not None, "Missing five-pixel strip model"
    result = create_inventory(db, model.device_type_id, model.key)
    header = result["config_header"]
    assert "#define LED_PIN 18" in header
    assert "#define LED_COUNT 5" in header
    assert "#define LILY_LED_STRIP 1" in header
    assert "I2S_BCLK_PIN" not in header


def test_device_model_change_preserves_identity_and_checks_compatibility(client, db, admin):
    from app.models.device import Device
    seed_models(db)
    model = db.get(DeviceModel, "lily_test_light")
    created = create_inventory(db, model.device_type_id, model.key, name="Strip 01")
    device = db.get(Device, created["device"]["id"])
    original_hash = device.secret_hash
    response = client.patch(f"/api/v1/devices/admin/{device.id}/model", headers=admin, json={"model_key":"lily_led_strip"})
    assert response.status_code == 200
    db.refresh(device)
    assert device.model == "Lily LED Strip" and device.name == "Strip 01"
    assert device.secret_hash == original_hash
    assert client.patch(f"/api/v1/devices/admin/{device.id}/model", headers=admin, json={"model_key":"lily_v1"}).status_code == 409
