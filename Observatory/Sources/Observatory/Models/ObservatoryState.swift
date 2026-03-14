import Foundation
import JoebotSDK
import Combine

@MainActor
final class ObservatoryState: ObservableObject {
    let nexusClient = NexusClient(clientId: "observatory", clientType: "monitor")
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        nexusClient.capabilitiesProvider = {
            [
                "monitor": true,
                "open_app_stub": true
            ]
        }

        // Forward NexusClient updates so monitor views refresh reliably.
        nexusClient.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var deviceCards: [NexusClientInfo] {
        nexusClient.connectedClients
            .filter { $0.clientId != nexusClient.clientId }
            .sorted { $0.clientId < $1.clientId }
    }
}
