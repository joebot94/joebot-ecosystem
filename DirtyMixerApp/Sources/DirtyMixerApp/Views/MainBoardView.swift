import JoebotSDK
import SwiftUI

struct MainBoardView: View {
    @ObservedObject var boardState: BoardState
    @AppStorage("joebot.appearance.dirtymixer") private var appearanceRawValue = StudioAppearancePreference.auto.rawValue

    private let columns = [
        GridItem(.flexible(minimum: 200), spacing: 14),
        GridItem(.flexible(minimum: 200), spacing: 14),
        GridItem(.flexible(minimum: 200), spacing: 14)
    ]

    private var appearancePreference: StudioAppearancePreference {
        StudioAppearancePreference(rawValue: appearanceRawValue) ?? .auto
    }

    private var useLiquidGlass: Bool {
        StudioAppearance.resolve(appearancePreference) == .liquid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            PresetBarView(boardState: boardState, useLiquidGlass: useLiquidGlass)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(boardState.channels) { channel in
                        ChannelStripView(channel: channel, useLiquidGlass: useLiquidGlass)
                    }
                }
            }
        }
        .padding(18)
        .background(
            Group {
                if useLiquidGlass {
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.16),
                            Color(red: 0.07, green: 0.09, blue: 0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                }
            }
        )
        .toolbar {
            ToolbarItemGroup {
                Button(boardState.mode.rawValue) {
                    boardState.toggleMode()
                }

                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(StudioAppearancePreference.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .frame(width: 110)

                Divider()

                NexusStatusIndicator(client: boardState.nexusClient)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("DirtyMixerApp")
                .font(.title2.weight(.bold))

            Spacer()

            Circle()
                .fill(boardState.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            Text(boardState.isConnected ? "Connected" : "Disconnected")
                .font(.callout.monospaced())

            Text(boardState.boardName)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(boardState.portName)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
