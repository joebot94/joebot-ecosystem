import Foundation

struct TimelineCue: Identifiable, Hashable {
    let id: UUID
    var time: Double
    var label: String

    init(id: UUID = UUID(), time: Double, label: String) {
        self.id = id
        self.time = time
        self.label = label
    }
}
