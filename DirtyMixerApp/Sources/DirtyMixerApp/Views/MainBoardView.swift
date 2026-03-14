import JoebotSDK
import SwiftUI

struct MainBoardView: View {
    @ObservedObject var boardState: BoardState

    private let columns = [
        GridItem(.flexible(minimum: 200), spacing: 14),
        GridItem(.flexible(minimum: 200), spacing: 14),
        GridItem(.flexible(minimum: 200), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            PresetBarView(boardState: boardState)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(boardState.channels) { channel in
                        ChannelStripView(channel: channel)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .toolbar {
            ToolbarItemGroup {
                Button(boardState.mode.rawValue) {
                    boardState.toggleMode()
                }

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
