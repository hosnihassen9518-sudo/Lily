import Foundation

private final class NoWidgetRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@available(iOS 15.0, *)
enum LilyWidgetAPI {
    private static let redirects = NoWidgetRedirects()
    private static func request(_ config: LilyWidgetConfig, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: config.backend_url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/widgets" + path),
              ["http", "https"].contains(url.scheme ?? "") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw NSError(domain: "LilyWidgetHTTP", code: code) }
        return data
    }
    static func run(deviceID: Int? = nil, enabled: Bool = false, expectedContext: String? = nil, expectedGeneration: Int? = nil) async -> LilyWidgetSnapshot {
        guard let config = LilyWidgetStore.config() else { return .empty }
        if let expectedContext, expectedContext != config.identity { return LilyWidgetStore.snapshot() }
        if config.expired { LilyWidgetStore.clear(expected: config.identity); return .empty }
        do {
            var snapshot: LilyWidgetSnapshot
            if let deviceID {
                guard LilyWidgetStore.snapshot().devices.contains(where: { $0.id == deviceID && $0.can_control }) else {
                    LilyWidgetStore.message("Device unavailable. Refresh first.", expected: config.identity)
                    return LilyWidgetStore.snapshot()
                }
                let data = try await request(config, "/devices/\(deviceID)/power", body: ["enabled": enabled, "expected_generation": expectedGeneration.map { $0 as Any } ?? NSNull()])
                struct PowerResponse: Decodable { let mqtt_published: Bool; let snapshot: LilyWidgetSnapshot }
                let response = try JSONDecoder().decode(PowerResponse.self, from: data)
                guard response.mqtt_published else { throw URLError(.cannotConnectToHost) }
                snapshot = response.snapshot
                snapshot.message = "Command sent. State updates after the next device report."
            } else {
                snapshot = try JSONDecoder().decode(LilyWidgetSnapshot.self, from: try await request(config, "/devices"))
            }
            LilyWidgetStore.save(snapshot, expected: config.identity)
        } catch {
            let error = error as NSError
            if error.domain == "LilyWidgetHTTP" && error.code == 401 { LilyWidgetStore.clear(expected: config.identity) }
            else { LilyWidgetStore.message("Could not update. Open Lily or try Refresh.", expected: config.identity) }
        }
        return LilyWidgetStore.snapshot()
    }
}
