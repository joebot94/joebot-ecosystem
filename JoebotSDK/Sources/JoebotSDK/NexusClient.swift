import Combine
import Foundation

@MainActor
public final class NexusClient: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var connectedClients: [NexusClientInfo] = []
    @Published public var statusText: String = "Disconnected"

    public let clientId: String
    public let clientType: String

    public var serverHost: String = "127.0.0.1"
    public var serverPort: Int = 8675
    public var autoConnect: Bool = true

    public var currentStateProvider: (() -> [String: Any])?
    public var capabilitiesProvider: (() -> [String: Any])?
    public var onMessage: ((NexusMessage) -> Void)?

    public var uptimeDescription: String {
        guard let connectedAt else { return "--" }
        let seconds = max(0, Int(Date().timeIntervalSince(connectedAt)))
        let mins = seconds / 60
        let rem = seconds % 60
        return String(format: "%02dm %02ds", mins, rem)
    }

    private var connectedAt: Date?
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private let session = URLSession(configuration: .default)
    private var clientMap: [String: NexusClientInfo] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var manualDisconnectRequested = false
    private let reconnectDelayNanoseconds: UInt64 = 2_000_000_000

    public init(clientId: String, clientType: String = "app") {
        self.clientId = clientId
        self.clientType = clientType
    }

    public func connect(to host: String, port: Int) {
        serverHost = host
        serverPort = port

        manualDisconnectRequested = false
        reconnectTask?.cancel()
        reconnectTask = nil
        resetConnectionState()

        guard let url = URL(string: "ws://\(host):\(port)") else {
            statusText = "Invalid URL"
            return
        }

        isConnecting = true
        statusText = "Connecting..."

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        Task {
            do {
                try await sendMessage(type: "register", payload: [
                    "client_id": clientId,
                    "client_type": clientType
                ])

                isConnected = true
                isConnecting = false
                connectedAt = Date()
                statusText = "Connected to \(host):\(port)"
                reconnectTask?.cancel()
                reconnectTask = nil
                startHeartbeat()
                receiveNextMessage(on: task)
            } catch {
                handleConnectionLost(reason: "Connect failed", error: error, retry: true)
            }
        }
    }

    public func disconnect() {
        manualDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil
        resetConnectionState()
        statusText = "Disconnected"
    }

    private func resetConnectionState() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        isConnected = false
        isConnecting = false
        connectedAt = nil
    }

    public func sendHeartbeat() {
        Task {
            try? await sendMessage(type: "heartbeat", payload: [
                "uptime_seconds": connectedAt.map { Date().timeIntervalSince($0) } ?? 0
            ])
        }
    }

    public func sendStateUpdate(_ state: [String: Any]) {
        Task {
            try? await sendMessage(type: "state_update", payload: ["state": state])
        }
    }

    public func sendIntent(targets: [String], action: String, params: [String: Any]) {
        Task {
            try? await sendMessage(type: "intent", payload: [
                "targets": targets,
                "action": action,
                "params": params
            ])
        }
    }

    public func requestCapabilities(of clientId: String) {
        Task {
            try? await sendMessage(type: "capabilities.query", payload: [
                "target_client_id": clientId,
                "target": clientId
            ])
        }
    }

    public func sendMessage(type: String, payload: [String: Any]) {
        Task {
            try? await sendMessage(type: type, payload: payload)
        }
    }

    private func receiveNextMessage(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.webSocketTask === task else { return }

                switch result {
                case let .success(message):
                    switch message {
                    case let .string(text):
                        self.handleIncomingText(text)
                    case let .data(data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleIncomingText(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveNextMessage(on: task)

                case let .failure(error):
                    self.handleConnectionLost(reason: "Disconnected", error: error, retry: true)
                }
            }
        }
    }

    private func handleConnectionLost(reason: String, error: Error? = nil, retry: Bool) {
        resetConnectionState()
        statusText = reason
        if let error {
            print("[NexusClient] \(reason.lowercased()) error: \(error)")
        }
        if retry {
            scheduleReconnectIfNeeded()
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard autoConnect, !manualDisconnectRequested else { return }
        guard reconnectTask == nil else { return }

        statusText = "Disconnected (retrying...)"
        let retryDelay = reconnectDelayNanoseconds
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: retryDelay)
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                guard self.autoConnect, !self.manualDisconnectRequested else { return }
                self.connect(to: self.serverHost, port: self.serverPort)
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let message = try? JSONDecoder().decode(NexusMessage.self, from: data) else {
            return
        }

        onMessage?(message)

        switch message.type {
        case "registered":
            isConnected = true
            isConnecting = false
            if connectedAt == nil {
                connectedAt = Date()
            }

        case "registry.snapshot":
            applyRegistrySnapshot(message)

        case "client.status":
            applyClientStatus(message)

        case "client.state":
            applyClientState(message)

        case "capabilities.query":
            respondToCapabilitiesQuery(message)

        case "scene.collect":
            respondToSceneCollect(message)

        default:
            break
        }
    }

    private func applyRegistrySnapshot(_ message: NexusMessage) {
        guard let rawClients = message.payload["clients"]?.anyValue as? [[String: Any]] else {
            return
        }

        clientMap.removeAll()
        for raw in rawClients {
            guard let clientId = raw["client_id"] as? String else { continue }
            let clientType = (raw["client_type"] as? String) ?? "app"
            let online = (raw["online"] as? Bool) ?? false
            let lastSeen = raw["last_seen"] as? String
            let summary = (raw["state_summary"] as? String) ?? "No state yet"
            clientMap[clientId] = NexusClientInfo(clientId: clientId, clientType: clientType, online: online, lastSeen: lastSeen, stateSummary: summary)
        }

        connectedClients = clientMap.values.sorted { $0.clientId < $1.clientId }
    }

    private func applyClientStatus(_ message: NexusMessage) {
        guard let clientId = message.payload["client_id"]?.anyValue as? String else {
            return
        }

        let clientType = (message.payload["client_type"]?.anyValue as? String) ?? "app"
        let online = (message.payload["online"]?.anyValue as? Bool) ?? false
        let lastSeen = message.payload["last_seen"]?.anyValue as? String
        let summary = (message.payload["state_summary"]?.anyValue as? String) ?? "No state yet"

        let info = NexusClientInfo(clientId: clientId, clientType: clientType, online: online, lastSeen: lastSeen, stateSummary: summary)
        clientMap[clientId] = info
        connectedClients = clientMap.values.sorted { $0.clientId < $1.clientId }
    }

    private func applyClientState(_ message: NexusMessage) {
        guard let clientId = message.payload["client_id"]?.anyValue as? String else {
            return
        }

        var existing = clientMap[clientId] ?? NexusClientInfo(clientId: clientId, clientType: "app", online: true)
        if let online = message.payload["online"]?.anyValue as? Bool {
            existing.online = online
        }
        if let summary = message.payload["state_summary"]?.anyValue as? String {
            existing.stateSummary = summary
        }
        if let clientType = message.payload["client_type"]?.anyValue as? String {
            existing = NexusClientInfo(
                clientId: existing.clientId,
                clientType: clientType,
                online: existing.online,
                lastSeen: existing.lastSeen,
                stateSummary: existing.stateSummary
            )
        }

        clientMap[clientId] = existing
        connectedClients = clientMap.values.sorted { $0.clientId < $1.clientId }
    }

    private func respondToCapabilitiesQuery(_ message: NexusMessage) {
        guard let requestId = message.payload["request_id"]?.anyValue as? String else {
            return
        }

        let capabilities = capabilitiesProvider?() ?? [:]
        sendMessage(type: "capabilities.result", payload: [
            "request_id": requestId,
            "capabilities": capabilities
        ])
    }

    private func respondToSceneCollect(_ message: NexusMessage) {
        guard let requestId = message.payload["request_id"]?.anyValue as? String else {
            return
        }

        let state = currentStateProvider?() ?? [:]
        sendMessage(type: "scene.state", payload: [
            "request_id": requestId,
            "state": state
        ])
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendHeartbeat()
            }
        }
    }

    private func sendMessage(type: String, payload: [String: Any]) async throws {
        guard let webSocketTask else {
            throw NSError(domain: "NexusClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        let message = NexusMessage(
            id: "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10))",
            type: type,
            source: clientId,
            payload: AnyCodable.wrapDictionary(payload)
        )

        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "NexusClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
