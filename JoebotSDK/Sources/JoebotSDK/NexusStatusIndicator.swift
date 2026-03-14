import SwiftUI

public struct NexusStatusIndicator: View {
    @ObservedObject public var client: NexusClient

    @State private var showingPopover = false
    @State private var hostField = "127.0.0.1"
    @State private var portField = "8675"

    public init(client: NexusClient) {
        self.client = client
    }

    public var body: some View {
        Button {
            hostField = client.serverHost
            portField = String(client.serverPort)
            showingPopover.toggle()
        } label: {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nexus")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $hostField)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("8675", text: $portField)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Auto-connect", isOn: Binding(
                    get: { client.autoConnect },
                    set: { client.autoConnect = $0 }
                ))

                Button(client.isConnected ? "Disconnect" : "Connect") {
                    if client.isConnected {
                        client.disconnect()
                    } else if let port = Int(portField) {
                        client.connect(to: hostField, port: port)
                    }
                }
                .buttonStyle(.borderedProminent)

                Divider()

                Text(client.statusText)
                    .font(.footnote.monospaced())
                Text("Uptime: \(client.uptimeDescription)")
                    .font(.footnote.monospaced())

                if !client.connectedClients.isEmpty {
                    Divider()
                    Text("Known Clients")
                        .font(.caption.weight(.semibold))
                    ForEach(client.connectedClients.prefix(6)) { info in
                        HStack {
                            Circle()
                                .fill(info.online ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            Text(info.clientId)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(info.clientType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    private var statusColor: Color {
        if client.isConnected {
            return .green
        }
        if client.isConnecting {
            return .yellow
        }
        return .red
    }
}
