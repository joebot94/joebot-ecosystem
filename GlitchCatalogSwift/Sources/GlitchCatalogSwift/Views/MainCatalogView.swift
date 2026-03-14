import JoebotSDK
import SwiftUI

private enum DOSTheme {
    static let navy = Color(red: 0.02, green: 0.06, blue: 0.28)
    static let panel = Color(red: 0.03, green: 0.13, blue: 0.38)
    static let cyan = Color(red: 0.35, green: 0.97, blue: 1.0)
    static let white = Color(red: 0.9, green: 0.96, blue: 1.0)
}

private struct DOSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .monospaced).weight(.bold))
            .foregroundStyle(DOSTheme.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? DOSTheme.cyan.opacity(0.2) : DOSTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(DOSTheme.cyan, lineWidth: 2)
            )
    }
}

struct MainCatalogView: View {
    @ObservedObject var state: CatalogState

    var body: some View {
        VStack(spacing: 0) {
            if !state.nexusClient.isConnected {
                Text("Nexus Offline")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(DOSTheme.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.65))
            }

            HStack(spacing: 10) {
                leftColumn
                middleColumn
                rightColumn
            }
            .padding(12)
        }
        .background(DOSTheme.navy)
        .foregroundStyle(DOSTheme.cyan)
        .toolbar {
            ToolbarItemGroup {
                Text("GLITCH CATALOG")
                    .font(.system(.headline, design: .monospaced).weight(.black))

                Button("Snapshot") {
                    state.sendSnapshot()
                }
                .buttonStyle(DOSButtonStyle())
                .disabled(!state.nexusClient.isConnected)

                Divider()

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
    }

    private var leftColumn: some View {
        panel(title: "SESSIONS") {
            List(selection: $state.selectedSessionID) {
                ForEach(state.sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.system(.body, design: .monospaced).weight(.bold))
                        Text("\(session.date) | \(session.location)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(DOSTheme.white.opacity(0.8))
                    }
                    .tag(session.id)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DOSTheme.panel)
        }
    }

    private var middleColumn: some View {
        panel(title: "TAPES + GEAR") {
            VStack(alignment: .leading, spacing: 10) {
                Text("TAPES")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                ForEach(state.tapesForSelectedSession, id: \.id) { tape in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tape.tapeID) [\(tape.format)]")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                        Text(tape.label)
                            .font(.system(.caption, design: .monospaced))
                        Text("@ \(tape.storageLocation)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(DOSTheme.white.opacity(0.8))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(DOSTheme.cyan, lineWidth: 1)
                    )
                }

                Divider()
                    .overlay(DOSTheme.cyan)

                Text("GEAR CHAIN")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                ForEach(Array(state.gearChainForSelectedSession.enumerated()), id: \.offset) { index, gearName in
                    Text("\(index + 1). \(gearName)")
                        .font(.system(.body, design: .monospaced))
                }

                Spacer()
            }
        }
    }

    private var rightColumn: some View {
        panel(title: "DIGITAL MEDIA") {
            List {
                ForEach(state.mediaForSelectedSession) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.filePath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Text("\(item.width)x\(item.height) • \(item.codec) • \(item.duration, specifier: "%.1f")s")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(DOSTheme.white.opacity(0.8))
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DOSTheme.panel)
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.black))
                .foregroundStyle(DOSTheme.white)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(DOSTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(DOSTheme.cyan, lineWidth: 2)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
