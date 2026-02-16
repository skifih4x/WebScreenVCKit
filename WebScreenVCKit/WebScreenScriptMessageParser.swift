import Foundation

internal enum WebScreenScriptMessageParser {
    static func isDebugLogMessage(_ body: Any) -> Bool {
        guard let messageString = body as? String else { return false }
        return messageString.hasPrefix("JS_LOG:") || messageString.hasPrefix("JS_ERROR:")
    }

    static func parse(_ body: Any) -> [String: Any]? {
        if let directDictionary = body as? [String: Any] {
            return directDictionary
        }

        if let jsonString = body as? String,
           let jsonData = jsonString.data(using: .utf8),
           let parsedDictionary = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return parsedDictionary
        }

        return nil
    }
}
