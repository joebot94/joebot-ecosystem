import Foundation

enum CueParamValueType: String, Hashable {
    case integer
    case decimal
    case boolean
    case option
    case bitset
}

struct CueParamOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: Double
}

struct CueParamDefinition: Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
    let valueType: CueParamValueType
    let stepValue: Double
    let options: [CueParamOption]
    let bitCount: Int

    init(
        id: String,
        key: String,
        name: String,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        valueType: CueParamValueType = .integer,
        stepValue: Double = 1,
        options: [CueParamOption] = [],
        bitCount: Int = 0
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.valueType = valueType
        self.stepValue = stepValue
        self.options = options
        self.bitCount = bitCount
    }
}

struct CueActionDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let params: [CueParamDefinition]
}

struct LibraryCueTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let actionID: String
    let params: [String: Double]
    let icon: String
}
