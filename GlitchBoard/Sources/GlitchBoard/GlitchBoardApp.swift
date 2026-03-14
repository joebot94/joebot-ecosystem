import SwiftUI

@main
struct GlitchBoardApp: App {
    @StateObject private var state = GlitchBoardState()

    var body: some Scene {
        WindowGroup {
            GlitchBoardMainView(state: state)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1120, minHeight: 760)
        }
    }
}
