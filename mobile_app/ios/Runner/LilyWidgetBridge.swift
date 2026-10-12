import Flutter
import Foundation

final class LilyWidgetBridge {
    static func register(_ registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "lily/widgets", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            do {
                switch call.method {
                case "supported":
                    if #available(iOS 17.0, *) { result(LilyWidgetStore.available) } else { result(false) }
                case "configure":
                    guard let data = call.arguments as? [String: Any] else { throw NSError(domain: "LilyWidgets", code: 3) }
                    try LilyWidgetStore.configure(data)
                    LilyWidgetStore.reload()
                    result(nil)
                case "update":
                    let bytes = try JSONSerialization.data(withJSONObject: call.arguments as Any)
                    LilyWidgetStore.save(try JSONDecoder().decode(LilyWidgetSnapshot.self, from: bytes))
                    LilyWidgetStore.reload()
                    result(nil)
                case "clear":
                    LilyWidgetStore.clear()
                    LilyWidgetStore.reload()
                    result(nil)
                default: result(FlutterMethodNotImplemented)
                }
            } catch { result(FlutterError(code: "WIDGET_SETUP", message: "Could not update widget configuration", details: nil)) }
        }
    }
}
