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
                    self?.publishState()
                }
                .store(in: &subscriptions)
        }
    }

    private func publishState() {
        nexusClient.sendStateUpdate(asPayloadState())
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
