import Combine
import Foundation
import JoebotSDK

enum ControlMode: String {
    case standalone = "Standalone"
    case managed = "Managed"
}

struct ChannelSnapshot {
    let id: Int
    let inputAEnabled: Bool
    let inputBEnabled: Bool
    let mix: Double
}

struct PresetSlot: Identifiable {
    let id: Int
    var name: String
    var snapshot: [ChannelSnapshot]?

    var hasData: Bool {
        snapshot != nil
    }
}

@MainActor
final class BoardState: ObservableObject {
    @Published var channels: [ChannelState]
    @Published var portName: String
    @Published var boardName: String
    @Published var mode: ControlMode
    @Published var presetSlots: [PresetSlot]

    let nexusClient: NexusClient

    private var subscriptions: Set<AnyCancellable> = []
    private var suppressStatePublishing = false

    init() {
        channels = (1...9).map { ChannelState(id: $0) }
        portName = "Nexus Port 8675"
        boardName = "DirtyMixer V1"
        mode = .managed
        presetSlots = (1...12).map { PresetSlot(id: $0, name: "Slot \($0)", snapshot: nil) }

        nexusClient = NexusClient(clientId: "dirtymixer_v1", clientType: "mixer")
        nexusClient.capabilitiesProvider = {
            [
                "state_update": true,
                "scene_collect": true,
                "intents": ["mix.set", "channel.toggle"]
            ]
        }

        nexusClient.currentStateProvider = { [weak self] in
            self?.asPayloadState() ?? [:]
        }
        nexusClient.onMessage = { [weak self] message in
            self?.handleNexusMessage(message)
        }

        // Forward NexusClient change notifications so board-level UI stays in sync.
        nexusClient.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        wireChannelObservers()
        connectToNexus()
    }

    var isConnected: Bool {
        nexusClient.isConnected
    }

    func connectToNexus() {
        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    func toggleMode() {
        mode = mode == .standalone ? .managed : .standalone
        publishState()
    }

    func savePreset(slot: Int) {
        guard let index = presetSlots.firstIndex(where: { $0.id == slot }) else { return }
        let snapshot = channels.map {
            ChannelSnapshot(id: $0.id, inputAEnabled: $0.inputAEnabled, inputBEnabled: $0.inputBEnabled, mix: $0.mix)
        }
        presetSlots[index].snapshot = snapshot
        presetSlots[index].name = "Preset \(slot)"
        publishState()
    }

    func recallPreset(slot: Int) {
        guard let index = presetSlots.firstIndex(where: { $0.id == slot }),
              let snapshot = presetSlots[index].snapshot
        else { return }

        for state in snapshot {
            guard let channel = channels.first(where: { $0.id == state.id }) else { continue }
            channel.inputAEnabled = state.inputAEnabled
            channel.inputBEnabled = state.inputBEnabled
            channel.mix = state.mix
        }
        publishState()
    }

    private func wireChannelObservers() {
        for channel in channels {
            channel.$inputAEnabled
                .combineLatest(channel.$inputBEnabled, channel.$mix)
                .dropFirst()
                .sink { [weak self] _, _, _ in
                    guard let self, !self.suppressStatePublishing else { return }
                    self.publishState()
                }
                .store(in: &subscriptions)
        }
    }

    private func publishState() {
        nexusClient.sendStateUpdate(asPayloadState())
    }

    private func handleNexusMessage(_ message: NexusMessage) {
        guard message.type == "scene.recall" else { return }
        guard let state = message.payload["state"]?.anyValue as? [String: Any] else { return }
        applyRecalledState(state)
    }

    private func applyRecalledState(_ state: [String: Any]) {
        suppressStatePublishing = true
        defer {
            suppressStatePublishing = false
            publishState()
        }

        if let modeValue = state["mode"] as? String, let restoredMode = ControlMode(rawValue: modeValue) {
            mode = restoredMode
        }

        guard let channelRows = state["channels"] as? [[String: Any]] else { return }
        for row in channelRows {
            guard let channelID = int(from: row["id"]),
                  let channel = channels.first(where: { $0.id == channelID })
            else {
                continue
            }

            if let inputA = bool(from: row["input_a"]) {
                channel.inputAEnabled = inputA
            }
            if let inputB = bool(from: row["input_b"]) {
                channel.inputBEnabled = inputB
            }
            if let mixValue = double(from: row["mix"]) {
                channel.mix = max(0, min(255, mixValue))
            }
        }
    }

    private func int(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    private func double(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            return nil
        }
    }

    private func bool(from value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        default:
            return nil
        }
    }

    private func asPayloadState() -> [String: Any] {
        [
            "board_name": boardName,
            "mode": mode.rawValue,
            "channels": channels.map { channel in
                [
                    "id": channel.id,
                    "input_a": channel.inputAEnabled,
                    "input_b": channel.inputBEnabled,
                    "mix": Int(channel.mix)
                ]
            },
            "preset_slots_with_data": presetSlots.filter { $0.hasData }.map(\.id)
        ]
    }
}
