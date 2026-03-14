import JoebotSDK
import SwiftUI

struct ObservatoryMainView: View {
    @ObservedObject var state: ObservatoryState
    @AppStorage("joebot.appearance.observatory") private var appearanceRawValue = StudioAppearancePreference.auto.rawValue

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 14)
    ]

    private var appearancePreference: StudioAppearancePreference {
        StudioAppearancePreference(rawValue: appearanceRawValue) ?? .auto
    }

    private var useLiquidGlass: Bool {
        StudioAppearance.resolve(appearancePreference) == .liquid
    }

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
                .background(mainBackground)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(state.deviceCards) { info in
                            DeviceCardView(info: info, useLiquidGlass: useLiquidGlass)
                        }
                    }
                    .padding(16)
                }
                .background(mainBackground)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Text("Observatory")
                    .font(.headline)

                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(StudioAppearancePreference.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .frame(width: 110)

                Spacer()

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
    }

    private var mainBackground: some View {
        Group {
            if useLiquidGlass {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.16),
                        Color(red: 0.07, green: 0.08, blue: 0.11),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(red: 0.08, green: 0.08, blue: 0.10)
            }
        }
    }
}
