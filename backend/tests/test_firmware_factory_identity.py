from pathlib import Path


def test_provisioned_factory_receipt_identity_precedes_generated_fallback():
    source = (Path(__file__).resolve().parents[2] / 'firmware_shared/src/device_lifecycle.cpp').read_text()
    function = source.split('String receiptKey() {', 1)[1].split('String publicKey()', 1)[0]
    assert function.index('strlen(DEVICE_RECEIPT_PRIVATE_KEY)') < function.index('storage.getString("receipt-key"')
