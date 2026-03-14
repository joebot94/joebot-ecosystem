import JoebotSDK
import SwiftUI

struct ObservatoryMainView: View {
    @ObservedObject var state: ObservatoryState

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !state.nexusClient.isConnected {
                HStack {
                    Text("Nexus Offline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.65))
            }

            if state.deviceCards.isEmpty {
                VStack(spacing: 10) {
                    Text("🦖")
                        .font(.system(size: 44))
                    Text("Waiting for connections...")
                        .font(.title3.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(state.deviceCards) { info in
                            DeviceCardView(info: info)
                        }
                    }
                    .padding(16)
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Text("Observatory")
                    .font(.headline)

                Spacer()

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
    }
}
