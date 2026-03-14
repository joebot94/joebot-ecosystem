import SwiftUI

@main
struct DirtyMixerApp: App {
    @StateObject private var boardState = BoardState()

    var body: some Scene {
        WindowGroup {
            MainBoardView(boardState: boardState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 760)
        }
    }
}
