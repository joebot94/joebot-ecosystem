import Foundation

public struct AnyCodable: Codable, Hashable {
    public let value: AnyHashable

    public init(_ value: Any?) {
        switch value {
        case let intValue as Int:
            self.value = intValue
        case let doubleValue as Double:
            self.value = doubleValue
        case let boolValue as Bool:
            self.value = boolValue
        case let stringValue as String:
            self.value = stringValue
        case let values as [String: Any]:
            self.value = AnyCodable.wrapDictionary(values)
        case let values as [Any]:
            self.value = AnyCodable.wrapArray(values)
        case let hashable as AnyHashable:
            self.value = hashable
        case nil:
            self.value = NSNull()
        default:
            self.value = String(describing: value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = intValue
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
            return
        }
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
            return
        }
        if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue
            return
        }
        if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let dictValue as [String: AnyCodable]:
            try container.encode(dictValue)
        case let arrayValue as [AnyCodable]:
            try container.encode(arrayValue)
        default:
            try container.encodeNil()
        }
    }

    public var anyValue: Any {
        switch value {
        case let dictValue as [String: AnyCodable]:
            return dictValue.mapValues { $0.anyValue }
        case let arrayValue as [AnyCodable]:
            return arrayValue.map { $0.anyValue }
        case is NSNull:
            return NSNull()
        default:
            return value
        }
    }

    public static func wrapDictionary(_ dictionary: [String: Any]) -> [String: AnyCodable] {
        dictionary.mapValues { AnyCodable($0) }
    }

    public static func wrapArray(_ values: [Any]) -> [AnyCodable] {
        values.map { AnyCodable($0) }
    }
}
