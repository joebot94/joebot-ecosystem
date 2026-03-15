import Foundation

@MainActor
final class PlayheadState: ObservableObject {
    @Published var playheadTime: Double = 0
    @Published var isPlaying: Bool = false
}
