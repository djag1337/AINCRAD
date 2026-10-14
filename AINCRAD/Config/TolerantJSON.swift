import Foundation

/// Decodes user JSON on top of defaults, so hand-edited files may omit any key.
enum TolerantJSON {
    static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) throws -> T {
        let user = try JSONSerialization.jsonObject(with: data)
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let merged = merge(base, user)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    static func merge(_ base: Any, _ over: Any) -> Any {
        guard let b = base as? [String: Any], let o = over as? [String: Any] else { return over }
        var out = b
        for (k, v) in o { out[k] = b[k].map { merge($0, v) } ?? v }
        return out
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value)
    }

    /// DecodingError's localizedDescription is useless to a user; name the key path instead.
    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        func path(_ c: DecodingError.Context) -> String {
            c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let key, let c): return "missing \"\(key.stringValue)\" at \(path(c))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            return "\(c.debugDescription) at \(path(c))"
        @unknown default: return e.localizedDescription
        }
    }
}
