"""Host-readable permission and source contracts; not native execution tests."""
import plistlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def test_app_keychain_default_is_private_and_extension_is_restricted():
    runner=plistlib.loads((ROOT/'mobile_app/ios/Runner/Runner.entitlements').read_bytes())
    extension=plistlib.loads((ROOT/'mobile_app/ios/LilyWidget/LilyWidget.entitlements').read_bytes())
    app='$(AppIdentifierPrefix)com.example.lilyMobile'
    shared=app+'.widgets'
    assert runner['keychain-access-groups']==[app,shared]
    assert extension['keychain-access-groups']==[shared]


def test_snapshot_readers_require_matching_current_account():
    android=(ROOT/'mobile_app/android/app/src/main/kotlin/com/example/lily_mobile/widgets/LilyWidgetStore.kt').read_text()
    ios=(ROOT/'mobile_app/ios/WidgetShared/WidgetStore.swift').read_text()
    assert 'value.optString("context_id")!=identity(current)' in android
    assert 'value.context_id == config.identity' in ios
    assert 'rawConfig() == nil ? .empty : rawSnapshot()' not in ios
