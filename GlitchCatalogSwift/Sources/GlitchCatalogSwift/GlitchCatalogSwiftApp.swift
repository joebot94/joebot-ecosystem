import SwiftUI

@main
struct GlitchCatalogSwiftApp: App {
    @StateObject private var state = CatalogState()

    var body: some Scene {
        WindowGroup {
            MainCatalogView(state: state)
                .frame(minWidth: 1120, minHeight: 720)
        }
    }
}
