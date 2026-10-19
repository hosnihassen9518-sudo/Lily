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
