import SwiftUI

@main
struct ObservatoryApp: App {
    @StateObject private var state = ObservatoryState()

    var body: some Scene {
        WindowGroup {
            ObservatoryMainView(state: state)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 700)
        }
    }
}
