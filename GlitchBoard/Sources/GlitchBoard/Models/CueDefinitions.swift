import Foundation

struct CueParamDefinition: Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
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
