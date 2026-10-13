from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def test_ble_setup_has_no_passkey_and_keeps_encryption():
    source = (ROOT / 'firmware_shared/src/ble_provisioning.cpp').read_text()
    assert 'setStaticPIN(' not in source
    assert 'ESP_LE_AUTH_REQ_SC_MITM_BOND' not in source
    assert 'ESP_LE_AUTH_REQ_SC_BOND' in source
    assert 'ESP_IO_CAP_NONE' in source
    assert 'ESP_GATT_PERM_READ_ENCRYPTED' in source
    assert 'ESP_GATT_PERM_WRITE_ENCRYPTED' in source
    assert 'if (!authenticated.load())' in source


def test_mobile_setup_does_not_request_a_pin():
    for relative in ('mobile_app/lib/screens/pair_device_screen.dart',
                     'mobile_app/lib/screens/device_management_screen.dart',
                     'mobile_app/lib/services/ble_provision_service.dart',
                     'mobile_app/android/app/src/main/kotlin/com/example/lily_mobile/MainActivity.kt'):
        source = (ROOT / relative).read_text().lower()
        assert 'pairing pin' not in source
        assert 'device pin' not in source
