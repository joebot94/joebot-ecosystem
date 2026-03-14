import Foundation

@MainActor
final class ChannelState: ObservableObject, Identifiable {
    let id: Int

    @Published var inputAEnabled: Bool
    @Published var inputBEnabled: Bool
    @Published var mix: Double

    init(id: Int, inputAEnabled: Bool = true, inputBEnabled: Bool = true, mix: Double = 128) {
        self.id = id
        self.inputAEnabled = inputAEnabled
        self.inputBEnabled = inputBEnabled
        self.mix = mix
    }

    var isActive: Bool {
        inputAEnabled || inputBEnabled
    }
}
