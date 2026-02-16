import Foundation

internal enum WebScreenURLBuilder {
    static func enrich(
        url: URL,
        appType: String,
        appID: String?,
        shouldAttachAppID: Bool,
        tokenProvider: WebScreenTokenProvider?,
        completion: @escaping (URL) -> Void
    ) {
        var components = URLComponents(string: url.absoluteString)
        var queryItems = components?.queryItems ?? []

        upsert(.init(name: "app_type", value: appType), in: &queryItems)

        if shouldAttachAppID, let appID {
            upsert(.init(name: "app_id", value: appID), in: &queryItems)
        }

        if let fcmToken = tokenProvider?.fcmToken(), !fcmToken.isEmpty {
            upsert(.init(name: "a_ssid", value: fcmToken), in: &queryItems)
        }

        guard let tokenProvider else {
            components?.queryItems = queryItems
            completion(components?.url ?? url)
            return
        }

        tokenProvider.mindboxUUID { uuid in
            var mutableItems = queryItems
            if !uuid.isEmpty {
                upsert(.init(name: "mb_uuid", value: uuid), in: &mutableItems)
            }

            components?.queryItems = mutableItems
            completion(components?.url ?? url)
        }
    }

    private static func upsert(_ item: URLQueryItem, in items: inout [URLQueryItem]) {
        items.removeAll { $0.name == item.name }
        items.append(item)
    }
}
