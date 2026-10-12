import WidgetKit
import SwiftUI
import AppIntents

struct LilyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LilyWidgetSnapshot
}
struct LilyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LilyWidgetEntry { .init(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (LilyWidgetEntry) -> Void) {
        completion(.init(date: Date(), snapshot: LilyWidgetStore.snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LilyWidgetEntry>) -> Void) {
        Task {
            let snapshot = await LilyWidgetAPI.run()
            completion(Timeline(entries: [.init(date: Date(), snapshot: snapshot)], policy: .after(Date().addingTimeInterval(900))))
        }
    }
}
struct LilyPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch a Lily device"
    static var openAppWhenRun = false
    @Parameter(title: "Device") var deviceID: Int
    @Parameter(title: "Enabled") var enabled: Bool
    @Parameter(title: "Account context") var contextID: String
    @Parameter(title: "Device generation") var generation: Int
    init() { deviceID = 0; enabled = false; contextID = ""; generation = -1 }
    init(deviceID: Int, enabled: Bool, contextID: String, generation: Int) { self.deviceID = deviceID; self.enabled = enabled; self.contextID = contextID; self.generation = generation }
    func perform() async throws -> some IntentResult {
        _ = await LilyWidgetAPI.run(deviceID: deviceID, enabled: enabled, expectedContext: contextID, expectedGeneration: generation >= 0 ? generation : nil)
        LilyWidgetStore.reload()
        return .result()
    }
}
struct LilyRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Lily devices"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        _ = await LilyWidgetAPI.run()
        LilyWidgetStore.reload()
        return .result()
    }
}
struct LilyWidgetView: View {
    let entry: LilyWidgetEntry
    @Environment(\.widgetFamily) var family
    private var maximum: Int { family == .systemLarge ? 4 : family == .systemMedium ? 2 : 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image("LilyCloud").resizable().scaledToFill().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Lily").font(.headline)
                Spacer()
                Button(intent: LilyRefreshIntent()) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh devices")
            }
            if entry.snapshot.devices.isEmpty {
                Text(entry.snapshot.message ?? "Open Lily to sign in or add a device.").font(.caption)
            } else {
                ForEach(Array(entry.snapshot.devices.prefix(maximum))) { device in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.caption.weight(.semibold)).lineLimit(2)
                            Text(device.status.replacingOccurrences(of: "_", with: " ")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        Button(intent: LilyPowerIntent(deviceID: device.id, enabled: true, contextID: entry.snapshot.context_id ?? "", generation: device.generation ?? -1)) { Text("On").font(.caption) }
                            .disabled(!device.can_control).accessibilityLabel("Turn \(device.name) on")
                        Button(intent: LilyPowerIntent(deviceID: device.id, enabled: false, contextID: entry.snapshot.context_id ?? "", generation: device.generation ?? -1)) { Text("Off").font(.caption) }
                            .disabled(!device.can_control).accessibilityLabel("Turn \(device.name) off")
                    }
                }
                if let message = entry.snapshot.message { Text(message).font(.caption2).lineLimit(2) }
                if entry.snapshot.devices.count > maximum { Text("Open Lily for more devices").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.21, green: 0.17, blue: 0.29))
        .tint(Color(red: 0.45, green: 0.35, blue: 0.67))
        .containerBackground(for: .widget) { Color(red: 1, green: 0.98, blue: 0.94) }
        .widgetURL(URL(string: "lily://widgets"))
    }
}
@main
struct LilyDevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LilyDevices", provider: LilyWidgetProvider()) { LilyWidgetView(entry: $0) }
            .configurationDisplayName("Lily devices")
            .description("See your devices and switch their power on or off.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
