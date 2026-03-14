import Foundation
import JoebotSDK

@MainActor
final class ObservatoryState: ObservableObject {
    let nexusClient = NexusClient(clientId: "observatory", clientType: "monitor")

    init() {
        nexusClient.capabilitiesProvider = {
            [
                "monitor": true,
                "open_app_stub": true
            ]
        }
        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var deviceCards: [NexusClientInfo] {
        nexusClient.connectedClients
            .filter { $0.clientId != nexusClient.clientId }
            .sorted { $0.clientId < $1.clientId }
    }
}
