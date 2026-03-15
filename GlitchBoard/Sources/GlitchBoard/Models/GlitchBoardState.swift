import AVFoundation
import AppKit
import Combine
import Foundation
import JoebotSDK
import UniformTypeIdentifiers

@MainActor
final class GlitchBoardState: NSObject, ObservableObject {
    @Published var bpm: Double = 140
    @Published var audioDuration: Double = 0
    @Published var playheadTime: Double = 0
    @Published var waveform: [Float] = []
    @Published var cues: [TimelineCue] = []
    @Published var selectedCueID: UUID?
    @Published var selectedCueLabelDraft = ""
    @Published var selectedAudioFileName = "No audio loaded"
    @Published var statusText = "Load a song to start building cues."
    @Published var isPlaying = false
    @Published var zoomScale: CGFloat = 1
    @Published var timelineViewportWidth: CGFloat = 1
    @Published var lanes: [CueLane] = GlitchBoardState.placeholderLanes
    @Published var projectName = "Untitled Show"
    @Published var activeProjectName = "No project loaded"
    @Published var showAutosaveRecoveryAlert = false
    @Published var libraryTemplates: [LibraryCueTemplate] = GlitchBoardState.defaultLibraryTemplates
    @Published var capabilityPollingEnabled = false
    @Published var lastCapabilitiesRefreshAt: Date?

    let nexusClient: NexusClient

    private var audioPlayer: AVAudioPlayer?
    private var loadedAudioURL: URL?
    private var playheadTimer: Timer?
    private var schedulerTimer: Timer?
    private var autosaveTimer: Timer?
    private var capabilitiesPollTimer: Timer?
    private var scheduledCueIDs: Set<UUID> = []
    private var scheduledRangeBuckets: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []
    private var requestedCapabilityTargets: Set<String> = []
    private var capabilitiesByClient: [String: [String: Any]] = [:]
    private var actionDefinitionsByClient: [String: [CueActionDefinition]] = [:]
    private var capabilityInfoByClient: [String: DeviceCapabilityInfo] = [:]

    private let schedulerInterval: TimeInterval = 0.05
    private let schedulerLookAhead: TimeInterval = 0.20
    private let rangeAutomationStep: TimeInterval = 0.05
    private let capabilitiesPollInterval: TimeInterval = 3.0
    private let capabilityBootstrapQueryEnabled = true

    private struct DeviceCapabilityInfo {
        var model: String?
        var actionCount: Int
        var inputCount: Int?
        var outputCount: Int?
    }

    private static let placeholderLanes: [CueLane] = [
        CueLane(
            id: "lane.dirty_mixer",
            name: "Dirty Mixer",
            target: "device.dirty_mixer.1",
            status: .offline,
            accentHex: "#FF6600",
            discoveryHints: ["dirtymixer", "dirty_mixer", "mixer"]
        ),
        CueLane(
            id: "lane.mtpx_1",
            name: "MTPX Plus #1",
            target: "device.mtpx.1",
            status: .offline,
            accentHex: "#00FFFF",
            discoveryHints: ["mtpx", "mtpx_plus"]
        ),
        CueLane(
            id: "lane.atlas_1",
            name: "Atlas",
            target: "device.atlas.1",
            status: .offline,
            accentHex: "#00FF88",
            discoveryHints: ["atlas", "extron"]
        ),
    ]

    private static let fallbackActions: [CueActionDefinition] = [
        CueActionDefinition(
            id: "glitchboard.cue.trigger",
            name: "glitchboard.cue.trigger",
            params: [
                CueParamDefinition(
                    id: "intensity",
                    key: "intensity",
                    name: "intensity",
                    minValue: 0,
                    maxValue: 255,
                    defaultValue: 127,
                    valueType: .integer,
                    stepValue: 1
                ),
            ]
        )
    ]

    private struct CapabilityProfile {
        let matchTokens: [String]
        let actions: [CueActionDefinition]
    }

    private static func intParam(_ key: String, _ name: String, min: Double, max: Double, default defaultValue: Double) -> CueParamDefinition {
        CueParamDefinition(
            id: key,
            key: key,
            name: name,
            minValue: min,
            maxValue: max,
            defaultValue: defaultValue,
            valueType: .integer,
            stepValue: 1
        )
    }

    private static func boolParam(_ key: String, _ name: String, default defaultValue: Bool = false) -> CueParamDefinition {
        CueParamDefinition(
            id: key,
            key: key,
            name: name,
            minValue: 0,
            maxValue: 1,
            defaultValue: defaultValue ? 1 : 0,
            valueType: .boolean,
            stepValue: 1
        )
    }

    private static func optionParam(_ key: String, _ name: String, options: [CueParamOption], default defaultValue: Double) -> CueParamDefinition {
        let minValue = options.map(\.value).min() ?? 0
        let maxValue = options.map(\.value).max() ?? 0
        return CueParamDefinition(
            id: key,
            key: key,
            name: name,
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            valueType: .option,
            stepValue: 1,
            options: options
        )
    }

    private static func bitmaskValue(indices: [Int], bitCount: Int) -> Double {
        guard bitCount > 0 else { return 0 }
        var mask = 0
        for index in indices where index >= 1 && index <= bitCount {
            mask |= (1 << (index - 1))
        }
        return Double(mask)
    }

    private static func bitsetParam(_ key: String, _ name: String, bits: Int, defaultIndices: [Int] = [1]) -> CueParamDefinition {
        let sanitizedBits = max(1, min(31, bits))
        let maxValue = Double((1 << sanitizedBits) - 1)
        return CueParamDefinition(
            id: key,
            key: key,
            name: name,
            minValue: 0,
            maxValue: maxValue,
            defaultValue: bitmaskValue(indices: defaultIndices, bitCount: sanitizedBits),
            valueType: .bitset,
            stepValue: 1,
            bitCount: sanitizedBits
        )
    }

    private static let bootstrapCapabilityProfiles: [CapabilityProfile] = [
        CapabilityProfile(
            matchTokens: ["mtpx", "extron"],
            actions: [
                CueActionDefinition(
                    id: "set_input_skew",
                    name: "set_input_skew",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 3),
                        intParam("red", "red", min: 0, max: 31, default: 0),
                        intParam("green", "green", min: 0, max: 31, default: 0),
                        intParam("blue", "blue", min: 0, max: 31, default: 0),
                    ]
                ),
                CueActionDefinition(
                    id: "set_input_skew_multi",
                    name: "set_input_skew_multi",
                    params: [
                        bitsetParam("input_mask", "input_mask", bits: 16, defaultIndices: [3]),
                        intParam("red", "red", min: 0, max: 31, default: 0),
                        intParam("green", "green", min: 0, max: 31, default: 0),
                        intParam("blue", "blue", min: 0, max: 31, default: 0),
                    ]
                ),
                CueActionDefinition(
                    id: "set_input_prepeak",
                    name: "set_input_prepeak",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 3),
                        intParam("level", "level", min: 0, max: 255, default: 127),
                    ]
                ),
                CueActionDefinition(
                    id: "recall_preset",
                    name: "recall_preset",
                    params: [
                        intParam("preset", "preset", min: 1, max: 32, default: 1),
                    ]
                ),
                CueActionDefinition(
                    id: "route_tie",
                    name: "route_tie",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 1),
                        intParam("output", "output", min: 1, max: 16, default: 1),
                        optionParam(
                            "mode",
                            "mode",
                            options: [
                                CueParamOption(id: "all", label: "all", value: 0),
                                CueParamOption(id: "rgb", label: "rgb", value: 1),
                                CueParamOption(id: "video", label: "video", value: 2),
                                CueParamOption(id: "audio", label: "audio", value: 3),
                            ],
                            default: 0
                        ),
                    ]
                ),
                CueActionDefinition(
                    id: "route_tie_multi",
                    name: "route_tie_multi",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 1),
                        bitsetParam("output_mask", "output_mask", bits: 16, defaultIndices: [1]),
                        optionParam(
                            "mode",
                            "mode",
                            options: [
                                CueParamOption(id: "all", label: "all", value: 0),
                                CueParamOption(id: "rgb", label: "rgb", value: 1),
                                CueParamOption(id: "video", label: "video", value: 2),
                                CueParamOption(id: "audio", label: "audio", value: 3),
                            ],
                            default: 0
                        ),
                    ]
                ),
            ]
        ),
        CapabilityProfile(
            matchTokens: ["dirty", "mixer"],
            actions: [
                CueActionDefinition(
                    id: "set_channel_mix",
                    name: "set_channel_mix",
                    params: [
                        intParam("channel", "channel", min: 1, max: 8, default: 1),
                        intParam("mix", "mix", min: 0, max: 255, default: 127),
                    ]
                ),
                CueActionDefinition(
                    id: "set_channel_mix_multi",
                    name: "set_channel_mix_multi",
                    params: [
                        bitsetParam("channel_mask", "channel_mask", bits: 8, defaultIndices: [1]),
                        intParam("mix", "mix", min: 0, max: 255, default: 127),
                    ]
                ),
                CueActionDefinition(
                    id: "set_channel_mute",
                    name: "set_channel_mute",
                    params: [
                        intParam("channel", "channel", min: 1, max: 8, default: 1),
                        boolParam("muted", "muted", default: false),
                    ]
                ),
                CueActionDefinition(
                    id: "recall_preset",
                    name: "recall_preset",
                    params: [
                        intParam("preset", "preset", min: 1, max: 32, default: 1),
                    ]
                ),
                CueActionDefinition(
                    id: "mix.ramp",
                    name: "mix.ramp",
                    params: [
                        intParam("start", "start", min: 0, max: 255, default: 0),
                        intParam("end", "end", min: 0, max: 255, default: 255),
                    ]
                ),
            ]
        ),
        CapabilityProfile(
            matchTokens: ["atlas", "ipcp", "relay"],
            actions: [
                CueActionDefinition(
                    id: "atlas.route",
                    name: "atlas.route",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 1),
                        intParam("output", "output", min: 1, max: 16, default: 1),
                    ]
                ),
                CueActionDefinition(
                    id: "atlas.route.multi",
                    name: "atlas.route.multi",
                    params: [
                        intParam("input", "input", min: 1, max: 16, default: 1),
                        bitsetParam("output_mask", "output_mask", bits: 16, defaultIndices: [1]),
                    ]
                ),
                CueActionDefinition(
                    id: "pulse_relay",
                    name: "pulse_relay",
                    params: [
                        intParam("relay", "relay", min: 1, max: 8, default: 1),
                    ]
                ),
                CueActionDefinition(
                    id: "recall_preset",
                    name: "recall_preset",
                    params: [
                        intParam("preset", "preset", min: 1, max: 32, default: 1),
                    ]
                ),
            ]
        ),
    ]

    private static let defaultLibraryTemplates: [LibraryCueTemplate] = [
        LibraryCueTemplate(id: "lib.max_blue", name: "Max Blue Separation", actionID: "set_input_skew", params: ["red": 0, "green": 0, "blue": 31], icon: "🔵"),
        LibraryCueTemplate(id: "lib.dirty_ramp", name: "Dirty Ramp", actionID: "mix.ramp", params: ["start": 0, "end": 255], icon: "🎚"),
        LibraryCueTemplate(id: "lib.atlas_route", name: "Atlas Route A", actionID: "atlas.route", params: ["route": 1], icon: "🟢"),
        LibraryCueTemplate(id: "lib.hit", name: "Hard Hit", actionID: "flash.hit", params: ["value": 255], icon: "⚡"),
    ]

    private static let shortClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    override init() {
        nexusClient = NexusClient(clientId: "glitchboard_v1", clientType: "daw")
        super.init()

        nexusClient.autoConnect = false
        nexusClient.serverHost = "localhost"
        nexusClient.serverPort = 8675

        nexusClient.capabilitiesProvider = { [weak self] in
            guard let self else { return [:] }
            return [
                "intents": ["glitchboard.cue.trigger"],
                "lane_targets": self.lanes.map(\.target),
            ]
        }

        nexusClient.currentStateProvider = { [weak self] in
            guard let self else { return [:] }
            return [
                "song": self.selectedAudioFileName,
                "bpm": self.bpm,
                "cue_count": self.cues.count,
                "lane_count": self.lanes.count,
            ]
        }

        nexusClient.onMessage = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleNexusMessage(message)
            }
        }

        loadCapabilitiesCache()
        wireNexusObservers()
        refreshLaneStatusesFromNexus()
        startAutosaveTimer()
        if capabilityPollingEnabled {
            startCapabilitiesPollingTimer()
        }
        showAutosaveRecoveryAlert = autosaveURL.fileExists
    }

    var beatDuration: Double {
        60 / max(bpm, 1)
    }

    var hasAudio: Bool {
        audioDuration > 0
    }

    var totalCueCount: Int {
        cues.count
    }

    var currentSongPositionString: String {
        formatClock(playheadTime)
    }

    var selectedCue: TimelineCue? {
        guard let selectedCueID else { return nil }
        return cues.first(where: { $0.id == selectedCueID })
    }

    var selectedCueSummary: String {
        guard let cue = selectedCue else { return "None" }
        let laneName = lanes.first(where: { $0.id == cue.laneID })?.name ?? "Unknown Lane"
        return "\(cue.label) • \(laneName) • \(barBeatString(for: cue.time))"
    }

    var timelineContentWidth: CGFloat {
        max(timelineViewportWidth, timelineViewportWidth * zoomScale)
    }

    var autosaveURL: URL {
        let folder = URL(fileURLWithPath: NSString(string: "~/JBT/glitchboard").expandingTildeInPath, isDirectory: true)
        return folder.appendingPathComponent("autosave.jbt", isDirectory: false)
    }

    var capabilitiesCacheURL: URL {
        autosaveURL.deletingLastPathComponent().appendingPathComponent("capabilities_cache.json", isDirectory: false)
    }

    var capabilityPollingStatus: String {
        capabilityPollingEnabled ? "On" : "Off"
    }

    var lastCapabilitiesRefreshLabel: String {
        guard let lastCapabilitiesRefreshAt else { return "--" }
        return Self.shortClockFormatter.string(from: lastCapabilitiesRefreshAt)
    }

    func cues(for laneID: String) -> [TimelineCue] {
        cues.filter { $0.laneID == laneID }.sorted { $0.time < $1.time }
    }

    func cueCount(for laneID: String) -> Int {
        cues(for: laneID).count
    }

    func setTimelineViewportWidth(_ width: CGFloat) {
        timelineViewportWidth = max(1, width)
    }

    func zoomIn() {
        zoomScale = min(8, zoomScale * 1.25)
    }

    func zoomOut() {
        zoomScale = max(1, zoomScale / 1.25)
    }

    func fitZoom() {
        zoomScale = 1
    }

    func availableActions(for laneID: String) -> [CueActionDefinition] {
        guard let lane = lanes.first(where: { $0.id == laneID }) else {
            return Self.fallbackActions
        }
        if let direct = actionDefinitionsByClient[lane.target], !direct.isEmpty {
            return direct
        }
        if let matched = actionDefinitionsByClient.first(where: { key, _ in
            lane.discoveryHints.contains(where: { key.lowercased().contains($0.lowercased()) })
        })?.value, !matched.isEmpty {
            return matched
        }
        if let bootstrap = bootstrapActions(for: lane), !bootstrap.isEmpty {
            return bootstrap
        }
        return Self.fallbackActions
    }

    func actionSourceLabel(for laneID: String) -> String {
        guard let lane = lanes.first(where: { $0.id == laneID }) else {
            return "Fallback"
        }
        if let direct = actionDefinitionsByClient[lane.target], !direct.isEmpty {
            return "Nexus"
        }
        if let matched = actionDefinitionsByClient.first(where: { key, value in
            !value.isEmpty && lane.discoveryHints.contains(where: { key.lowercased().contains($0.lowercased()) })
        })?.value, !matched.isEmpty {
            return "Nexus"
        }
        if let bootstrap = bootstrapActions(for: lane), !bootstrap.isEmpty {
            return "Bootstrapped"
        }
        return "Fallback"
    }

    func laneCapabilitySummary(for laneID: String) -> String {
        guard let lane = lanes.first(where: { $0.id == laneID }) else { return "No capability data" }
        let actions = availableActions(for: laneID)
        let source = actionSourceLabel(for: laneID)
        if let info = capabilityInfo(for: lane) {
            var parts: [String] = ["\(info.actionCount) actions"]
            if let inputs = info.inputCount, let outputs = info.outputCount {
                parts.append("\(inputs)x\(outputs) I/O")
            } else if let inputs = info.inputCount {
                parts.append("\(inputs) inputs")
            } else if let outputs = info.outputCount {
                parts.append("\(outputs) outputs")
            }
            if let model = info.model, !model.isEmpty {
                parts.append(model)
            }
            return "\(source) • " + parts.joined(separator: " • ")
        }

        return "\(source) • \(actions.count) actions"
    }

    func toggleCapabilityPolling() {
        capabilityPollingEnabled.toggle()
        if capabilityPollingEnabled {
            startCapabilitiesPollingTimer()
            refreshCapabilitiesNow()
        } else {
            stopCapabilitiesPollingTimer()
            statusText = "Capability polling disabled"
        }
    }

    func refreshCapabilitiesNow() {
        guard nexusClient.isConnected else {
            statusText = "Nexus offline: using cached and bootstrapped capabilities"
            return
        }
        requestCapabilitiesForOnlineClients(force: true)
        lastCapabilitiesRefreshAt = Date()
        statusText = "Requested capability refresh"
    }

    func actionDefinition(for laneID: String, actionID: String) -> CueActionDefinition? {
        availableActions(for: laneID).first(where: { $0.id == actionID })
    }

    func resolvedActionID(for cue: TimelineCue) -> String {
        let actions = availableActions(for: cue.laneID)
        if actions.contains(where: { $0.id == cue.actionID }) {
            return cue.actionID
        }
        return actions.first?.id ?? cue.actionID
    }

    func updateSelectedCueLane(_ laneID: String) {
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        cues[index].laneID = laneID
        cues[index].deviceTarget = lanes.first(where: { $0.id == laneID })?.target ?? cues[index].deviceTarget

        let actions = availableActions(for: laneID)
        if actions.contains(where: { $0.id == cues[index].actionID }) == false,
           let fallback = actions.first
        {
            cues[index].actionID = fallback.id
            applyDefaultParams(forCueAt: index, using: fallback)
        }
    }

    func updateSelectedCueAction(_ actionID: String) {
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        cues[index].actionID = actionID
        if let action = actionDefinition(for: cues[index].laneID, actionID: actionID) {
            applyDefaultParams(forCueAt: index, using: action)
        }
    }

    func updateSelectedCueParam(key: String, value: Double) {
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        cues[index].params[key] = normalizedParamValue(
            key: key,
            value: value,
            laneID: cues[index].laneID,
            actionID: cues[index].actionID
        )
    }

    func updateSelectedRangeParam(key: String, startValue: Double, endValue: Double) {
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        cues[index].startParams[key] = normalizedParamValue(
            key: key,
            value: startValue,
            laneID: cues[index].laneID,
            actionID: cues[index].actionID
        )
        cues[index].endParams[key] = normalizedParamValue(
            key: key,
            value: endValue,
            laneID: cues[index].laneID,
            actionID: cues[index].actionID
        )
    }

    func setCueMute(_ cueID: UUID, muted: Bool) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
        cues[index].muted = muted
        statusText = muted ? "Cue muted" : "Cue unmuted"
    }

    func updateSelectedCueInterpolation(_ interpolation: CueInterpolation) {
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        cues[index].interpolation = interpolation
    }

    func promptSaveProject() {
        let panel = NSSavePanel()
        panel.title = "Save GlitchBoard Setlist"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "jbt") ?? .json, .json]
        panel.nameFieldStringValue = "\(safeProjectFileName()).jbt"

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        let destination = chosenURL.pathExtension.isEmpty ? chosenURL.appendingPathExtension("jbt") : chosenURL
        saveSetlist(to: destination, isAutosave: false)
    }

    func promptLoadProject() {
        let panel = NSOpenPanel()
        panel.title = "Open GlitchBoard Setlist"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jbt") ?? .json, .json]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        loadSetlist(from: sourceURL)
    }

    func recoverAutosave() {
        loadSetlist(from: autosaveURL)
        showAutosaveRecoveryAlert = false
    }

    func discardAutosave() {
        try? FileManager.default.removeItem(at: autosaveURL)
        showAutosaveRecoveryAlert = false
    }

    func loadAudio(from url: URL) {
        stop()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player

            loadedAudioURL = url
            audioDuration = player.duration
            playheadTime = 0
            selectedAudioFileName = url.lastPathComponent
            selectCue(nil)
            clearScheduledDispatchState()
            statusText = "Loaded \(selectedAudioFileName)"
            fitZoom()

            Task.detached(priority: .userInitiated) {
                let samples = (try? Self.extractWaveform(url: url, targetSampleCount: 2400)) ?? []
                await MainActor.run {
                    self.waveform = samples
                }
            }
        } catch {
            statusText = "Could not load audio: \(error.localizedDescription)"
            clearAudioState()
        }
    }

    func play() {
        guard let audioPlayer else {
            statusText = "Load audio before playback."
            return
        }

        if playheadTime >= audioDuration - 0.001 {
            audioPlayer.currentTime = 0
            playheadTime = 0
            clearScheduledDispatchState()
        }

        guard !audioPlayer.isPlaying else { return }
        audioPlayer.play()
        isPlaying = true
        startPlayheadTimer()
        startSchedulerTimer()
        statusText = "Playing \(selectedAudioFileName)"
    }

    func pause() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        audioPlayer.pause()
        isPlaying = false
        stopPlayheadTimer()
        stopSchedulerTimer()
        clearScheduledDispatchState()
        statusText = "Paused"
    }

    func stop() {
        if let audioPlayer {
            audioPlayer.stop()
            audioPlayer.currentTime = 0
        }
        isPlaying = false
        playheadTime = 0
        stopPlayheadTimer()
        stopSchedulerTimer()
        clearScheduledDispatchState()
        statusText = "Stopped"
    }

    func clearCues(for laneID: String) {
        cues.removeAll { $0.laneID == laneID }
        if let selectedCueID, cues.contains(where: { $0.id == selectedCueID }) == false {
            selectCue(nil)
        }
        let validCueIDs = Set(cues.map(\.id))
        scheduledCueIDs = scheduledCueIDs.intersection(validCueIDs)
        scheduledRangeBuckets = scheduledRangeBuckets.filter { bucket in
            validCueIDs.contains { bucket.hasPrefix($0.uuidString) }
        }
        statusText = "Cleared cues for \(laneName(for: laneID))"
    }

    func selectCue(_ cueID: UUID?) {
        selectedCueID = cueID
        if let cueID, let index = cues.firstIndex(where: { $0.id == cueID }) {
            let resolvedAction = resolvedActionID(for: cues[index])
            if cues[index].actionID != resolvedAction {
                cues[index].actionID = resolvedAction
                if let action = actionDefinition(for: cues[index].laneID, actionID: resolvedAction) {
                    applyDefaultParams(forCueAt: index, using: action)
                }
            }
            let cue = cues[index]
            selectedCueLabelDraft = cue.label
        } else {
            selectedCueLabelDraft = ""
        }
    }

    func updateSelectedCueLabel(_ newLabel: String) {
        selectedCueLabelDraft = newLabel
        guard let selectedCueID, let index = cues.firstIndex(where: { $0.id == selectedCueID }) else { return }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        cues[index].label = trimmed.isEmpty ? "Cue" : trimmed
    }

    func deleteSelectedCue() {
        guard let selectedCueID else { return }
        deleteCue(selectedCueID)
    }

    func deleteCue(_ cueID: UUID) {
        let hadCue = cues.contains { $0.id == cueID }
        cues.removeAll { $0.id == cueID }
        if hadCue {
            scheduledCueIDs.remove(cueID)
            scheduledRangeBuckets = scheduledRangeBuckets.filter { !$0.hasPrefix(cueID.uuidString) }
            if selectedCueID == cueID {
                selectCue(nil)
            }
            statusText = "Deleted cue"
        }
    }

    func duplicateCue(_ cueID: UUID) {
        guard let cue = cues.first(where: { $0.id == cueID }) else { return }
        var copy = cue
        copy.id = UUID()
        copy.time = min(audioDuration, cue.time + beatDuration)
        if let endTime = cue.endTime {
            copy.endTime = min(audioDuration, endTime + beatDuration)
        }
        cues.append(copy)
        cues.sort { $0.time < $1.time }
        selectCue(copy.id)
        statusText = "Duplicated cue"
    }

    func toggleMute(_ cueID: UUID) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
        setCueMute(cueID, muted: !cues[index].muted)
    }

    func cycleInterpolation(for cueID: UUID) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
        guard cues[index].kind == .range else { return }
        let next = CueInterpolation.allCases
        if let currentIndex = next.firstIndex(of: cues[index].interpolation) {
            cues[index].interpolation = next[(currentIndex + 1) % next.count]
        }
    }

    func updateCueBoundary(cueID: UUID, isStart: Bool, xPosition: CGFloat, laneWidth: CGFloat) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
        guard cues[index].kind == .range else { return }
        guard laneWidth > 0 else { return }

        let normalized = max(0, min(1, xPosition / laneWidth))
        let snapped = snapToQuarterNote(Double(normalized) * audioDuration)
        let end = cues[index].endTime ?? cues[index].time

        if isStart {
            cues[index].time = min(snapped, end)
        } else {
            cues[index].endTime = max(snapped, cues[index].time)
        }
    }

    func handleLaneTap(laneID: String, xPosition: CGFloat, laneWidth: CGFloat) {
        guard hasAudio else {
            statusText = "Load audio first to place cues."
            return
        }
        guard laneWidth > 0 else { return }

        let normalized = max(0, min(1, xPosition / laneWidth))
        let tapTime = Double(normalized) * audioDuration
        let timeTolerance = Double(12 / laneWidth) * audioDuration

        if let nearbyCue = cues(for: laneID).min(by: {
            abs($0.time - tapTime) < abs($1.time - tapTime)
        }), abs(nearbyCue.time - tapTime) <= timeTolerance {
            selectCue(nearbyCue.id)
            statusText = "Selected \(nearbyCue.label) at \(barBeatString(for: nearbyCue.time))"
            return
        }

        placeOneShotCue(in: laneID, at: normalized, fromTemplate: nil)
    }

    func createRangeCue(in laneID: String, startX: CGFloat, endX: CGFloat, laneWidth: CGFloat) {
        guard hasAudio, laneWidth > 0 else { return }
        let left = max(0, min(1, min(startX, endX) / laneWidth))
        let right = max(0, min(1, max(startX, endX) / laneWidth))
        let startTime = snapToQuarterNote(Double(left) * audioDuration)
        let endTime = snapToQuarterNote(Double(right) * audioDuration)
        guard endTime - startTime >= beatDuration * 0.5 else { return }

        let action = availableActions(for: laneID).first ?? Self.fallbackActions[0]
        let defaults = Dictionary(uniqueKeysWithValues: action.params.map { ($0.key, $0.defaultValue) })
        let laneTarget = lanes.first(where: { $0.id == laneID })?.target ?? ""
        let cue = TimelineCue(
            laneID: laneID,
            time: startTime,
            endTime: endTime,
            label: "Cue",
            muted: false,
            deviceTarget: laneTarget,
            actionID: action.id,
            params: defaults,
            startParams: defaults,
            endParams: defaults,
            kind: .range,
            interpolation: .linear
        )
        cues.append(cue)
        cues.sort { $0.time < $1.time }
        selectCue(cue.id)
        statusText = "Placed range cue at \(barBeatString(for: cue.time))"
    }

    func dropLibraryCue(templateID: String, laneID: String, xPosition: CGFloat, laneWidth: CGFloat) {
        guard let template = libraryTemplates.first(where: { $0.id == templateID }) else { return }
        let normalized = max(0, min(1, xPosition / max(1, laneWidth)))
        placeOneShotCue(in: laneID, at: normalized, fromTemplate: template)
    }

    func cueTooltip(_ cue: TimelineCue) -> String {
        let laneName = lanes.first(where: { $0.id == cue.laneID })?.name ?? cue.laneID
        let values = cue.params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let base = "\(laneName) • \(cue.actionID) • \(barBeatString(for: cue.time))"
        return values.isEmpty ? base : "\(base)\n\(values)"
    }

    func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard audioDuration > 0 else { return 0 }
        return CGFloat(time / audioDuration) * width
    }

    func barBeatString(for time: Double) -> String {
        let beatIndex = max(0, Int(floor(time / beatDuration)))
        let bar = (beatIndex / 4) + 1
        let beat = (beatIndex % 4) + 1
        return "Bar \(bar) Beat \(beat)"
    }

    func songProgressDetail() -> String {
        "\(formatClock(playheadTime)) / \(formatClock(audioDuration))"
    }

    private func laneName(for laneID: String) -> String {
        lanes.first(where: { $0.id == laneID })?.name ?? "Unknown Lane"
    }

    private func placeOneShotCue(in laneID: String, at normalizedPosition: CGFloat, fromTemplate template: LibraryCueTemplate?) {
        let unclamped = Double(normalizedPosition) * audioDuration
        let snappedTime = snapToQuarterNote(unclamped)
        let action = template?.actionID ?? availableActions(for: laneID).first?.id ?? Self.fallbackActions[0].id
        let actionDef = actionDefinition(for: laneID, actionID: action) ?? Self.fallbackActions[0]
        let defaultParams = Dictionary(uniqueKeysWithValues: actionDef.params.map { ($0.key, $0.defaultValue) })
        var cueParams = defaultParams
        if let template {
            cueParams.merge(template.params) { _, new in new }
        }
        let laneTarget = lanes.first(where: { $0.id == laneID })?.target ?? ""
        let cue = TimelineCue(
            laneID: laneID,
            time: snappedTime,
            label: template?.name ?? "Cue",
            muted: false,
            deviceTarget: laneTarget,
            actionID: action,
            params: cueParams,
            startParams: cueParams,
            endParams: cueParams,
            kind: .oneShot,
            interpolation: .linear
        )
        cues.append(cue)
        cues.sort { $0.time < $1.time }
        selectCue(cue.id)
        statusText = "Placed \(cue.label) at \(barBeatString(for: snappedTime))"
    }

    private func applyDefaultParams(forCueAt index: Int, using action: CueActionDefinition) {
        let defaults = Dictionary(uniqueKeysWithValues: action.params.map { ($0.key, $0.defaultValue) })
        cues[index].params = defaults
        cues[index].startParams = defaults
        cues[index].endParams = defaults
    }

    private func bootstrapActions(for lane: CueLane) -> [CueActionDefinition]? {
        let lookup = "\(lane.name) \(lane.target) \(lane.discoveryHints.joined(separator: " "))".lowercased()
        return Self.bootstrapCapabilityProfiles.first(where: { profile in
            profile.matchTokens.contains(where: { token in lookup.contains(token.lowercased()) })
        })?.actions
    }

    private func normalizedParamValue(key: String, value: Double, laneID: String, actionID: String) -> Double {
        guard let action = actionDefinition(for: laneID, actionID: actionID),
              let definition = action.params.first(where: { $0.key == key })
        else {
            return value
        }

        var normalized = min(max(value, definition.minValue), definition.maxValue)

        if !definition.options.isEmpty {
            if let closest = definition.options.min(by: { abs($0.value - normalized) < abs($1.value - normalized) }) {
                normalized = closest.value
            }
            return normalized
        }

        switch definition.valueType {
        case .boolean:
            return normalized >= 0.5 ? 1 : 0
        case .integer:
            return normalized.rounded()
        case .decimal:
            return normalized
        case .option:
            return normalized.rounded()
        case .bitset:
            return normalized.rounded()
        }
    }

    private func serializeParamsForDispatch(cue: TimelineCue, rawValues: [String: Double]) -> [String: Any] {
        guard let action = actionDefinition(for: cue.laneID, actionID: cue.actionID) else {
            return rawValues
        }
        let definitions = Dictionary(uniqueKeysWithValues: action.params.map { ($0.key, $0) })
        var payload: [String: Any] = [:]
        for (key, rawValue) in rawValues {
            guard let definition = definitions[key] else {
                payload[key] = rawValue
                continue
            }

            let normalized = normalizedParamValue(key: key, value: rawValue, laneID: cue.laneID, actionID: cue.actionID)
            switch definition.valueType {
            case .boolean:
                payload[key] = normalized >= 0.5
            case .integer, .option, .bitset:
                payload[key] = Int(normalized.rounded())
            case .decimal:
                payload[key] = normalized
            }
        }
        return payload
    }

    private func startPlayheadTimer() {
        stopPlayheadTimer()
        playheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            Task { @MainActor [weak self] in
                self?.updatePlayhead()
            }
        }
        if let playheadTimer {
            RunLoop.main.add(playheadTimer, forMode: .common)
        }
    }

    private func stopPlayheadTimer() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func startSchedulerTimer() {
        stopSchedulerTimer()
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: schedulerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleUpcomingCueDispatches()
            }
        }
        if let schedulerTimer {
            RunLoop.main.add(schedulerTimer, forMode: .common)
        }
    }

    private func stopSchedulerTimer() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil
    }

    private func clearScheduledDispatchState() {
        scheduledCueIDs.removeAll()
        scheduledRangeBuckets.removeAll()
    }

    private func scheduleUpcomingCueDispatches() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        let now = audioPlayer.currentTime
        let windowEnd = min(audioDuration, now + schedulerLookAhead)

        for cue in cues where !cue.muted {
            guard let lane = lanes.first(where: { $0.id == cue.laneID }) else { continue }

            switch cue.kind {
            case .oneShot:
                guard cue.time >= now, cue.time <= windowEnd else { continue }
                guard !scheduledCueIDs.contains(cue.id) else { continue }
                scheduledCueIDs.insert(cue.id)

                let delay = max(0, cue.time - now)
                let cueID = cue.id
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.dispatchOneShotCue(cueID: cueID)
                    }
                }

            case .range:
                guard let endTime = cue.endTime else { continue }
                guard endTime >= now, cue.time <= windowEnd else { continue }

                var sampleTime = max(now, cue.time)
                while sampleTime <= min(endTime, windowEnd) + 0.0001 {
                    let bucketIndex = Int((sampleTime / rangeAutomationStep).rounded())
                    let bucketKey = "\(cue.id.uuidString)#\(bucketIndex)"
                    guard !scheduledRangeBuckets.contains(bucketKey) else {
                        sampleTime += rangeAutomationStep
                        continue
                    }

                    scheduledRangeBuckets.insert(bucketKey)
                    let dispatchDelay = max(0, sampleTime - now)
                    let cueID = cue.id
                    let laneTarget = lane.target
                    let laneName = lane.name
                    let dispatchTime = sampleTime
                    DispatchQueue.main.asyncAfter(deadline: .now() + dispatchDelay) { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.dispatchRangeStep(
                                cueID: cueID,
                                laneTarget: laneTarget,
                                laneName: laneName,
                                atTime: dispatchTime
                            )
                        }
                    }

                    sampleTime += rangeAutomationStep
                }
            }
        }
    }

    private func dispatchOneShotCue(cueID: UUID) {
        guard let cue = cues.first(where: { $0.id == cueID }) else { return }
        guard !cue.muted else { return }
        guard let lane = lanes.first(where: { $0.id == cue.laneID }) else { return }

        var payload: [String: Any] = serializeParamsForDispatch(cue: cue, rawValues: cue.params)
        payload["cue_id"] = cue.id.uuidString
        payload["label"] = cue.label
        payload["bar_beat"] = barBeatString(for: cue.time)
        payload["type"] = cue.kind.rawValue

        nexusClient.sendIntent(targets: [lane.target], action: cue.actionID, params: payload)
        statusText = "Fired \(cue.label) on \(lane.name)"
    }

    private func dispatchRangeStep(cueID: UUID, laneTarget: String, laneName: String, atTime playbackTime: Double) {
        guard let cue = cues.first(where: { $0.id == cueID }) else { return }
        guard cue.kind == .range, !cue.muted else { return }
        guard let endTime = cue.endTime, endTime > cue.time else { return }
        guard playbackTime >= cue.time, playbackTime <= endTime + 0.0001 else { return }

        let progress = min(max((playbackTime - cue.time) / (endTime - cue.time), 0), 1)
        let curveProgress: Double
        switch cue.interpolation {
        case .linear:
            curveProgress = progress
        case .step:
            curveProgress = floor(progress * 8) / 8
        case .triangle:
            curveProgress = 1 - abs((progress * 2) - 1)
        }

        var interpolatedValues: [String: Double] = [:]
        let keys = Set(cue.startParams.keys).union(cue.endParams.keys).union(cue.params.keys)
        for key in keys {
            let startValue = cue.startParams[key] ?? cue.params[key] ?? 0
            let endValue = cue.endParams[key] ?? cue.params[key] ?? startValue
            interpolatedValues[key] = startValue + (endValue - startValue) * curveProgress
        }
        var payload: [String: Any] = serializeParamsForDispatch(cue: cue, rawValues: interpolatedValues)
        payload["cue_id"] = cue.id.uuidString
        payload["label"] = cue.label
        payload["interpolation"] = cue.interpolation.rawValue
        payload["progress"] = curveProgress
        payload["type"] = cue.kind.rawValue
        payload["bar_beat"] = barBeatString(for: playbackTime)

        nexusClient.sendIntent(targets: [laneTarget], action: cue.actionID, params: payload)
        statusText = "Automating \(cue.label) on \(laneName)"
    }

    private func updatePlayhead() {
        guard let audioPlayer else { return }
        let current = min(audioDuration, audioPlayer.currentTime)
        playheadTime = current

        if !audioPlayer.isPlaying, current >= audioDuration - 0.001 {
            isPlaying = false
            stopPlayheadTimer()
            stopSchedulerTimer()
            clearScheduledDispatchState()
            statusText = "Stopped"
        }
    }

    private func snapToQuarterNote(_ time: Double) -> Double {
        let snappedBeatIndex = (time / beatDuration).rounded()
        let snappedTime = snappedBeatIndex * beatDuration
        return min(max(0, snappedTime), audioDuration)
    }

    private func formatClock(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "00:00.0" }
        let minutes = Int(time / 60)
        let seconds = time - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, seconds)
    }

    private func clearAudioState() {
        audioPlayer = nil
        loadedAudioURL = nil
        waveform = []
        audioDuration = 0
        playheadTime = 0
        selectedAudioFileName = "No audio loaded"
    }

    private func safeProjectFileName() -> String {
        let base = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "glitchboard_setlist"
        }
        return base.replacingOccurrences(of: "/", with: "-")
    }

    private func saveSetlist(to url: URL, isAutosave: Bool) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let setlist = makeSetlistDocument()
            let data = try encoder.encode(setlist)
            try data.write(to: url, options: .atomic)
            if isAutosave {
                return
            }
            activeProjectName = url.lastPathComponent
            statusText = "Saved setlist to \(url.lastPathComponent)"
        } catch {
            statusText = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadSetlist(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let setlist = try? decoder.decode(JBTSetlistFile.self, from: data), setlist.jbtType == "daw_setlist" {
                try validateSetlist(setlist)
                applySetlist(setlist, sourceURL: url)
                activeProjectName = url.lastPathComponent
                statusText = "Loaded setlist \(url.lastPathComponent)"
                return
            }

            if let legacy = try? decoder.decode(JBTProjectFile.self, from: data) {
                applyLegacyProject(legacy, sourceURL: url)
                activeProjectName = url.lastPathComponent
                statusText = "Loaded legacy project \(url.lastPathComponent)"
                return
            }

            statusText = "Load failed: unsupported .jbt format"
        } catch {
            statusText = "Load failed: \(error.localizedDescription)"
        }
    }

    private func validateSetlist(_ setlist: JBTSetlistFile) throws {
        guard setlist.jbtType == "daw_setlist" else {
            throw NSError(domain: "GlitchBoard", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Expected jbt_type=daw_setlist"])
        }
        guard !setlist.version.isEmpty else {
            throw NSError(domain: "GlitchBoard", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Missing version"])
        }
        guard !setlist.payload.songs.isEmpty else {
            throw NSError(domain: "GlitchBoard", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Setlist has no songs"])
        }
        let laneIDs = Set(setlist.payload.deviceLanes.map(\.deviceID))
        for cue in setlist.payload.songs.flatMap(\.cues) {
            guard !cue.id.isEmpty else {
                throw NSError(domain: "GlitchBoard", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Cue id is empty"])
            }
            guard !cue.deviceID.isEmpty else {
                throw NSError(domain: "GlitchBoard", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Cue device_id is empty"])
            }
            guard !cue.action.isEmpty else {
                throw NSError(domain: "GlitchBoard", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Cue action is empty"])
            }
            if !laneIDs.isEmpty, !laneIDs.contains(cue.deviceID) {
                throw NSError(domain: "GlitchBoard", code: 1007, userInfo: [NSLocalizedDescriptionKey: "Cue references unknown device_id \(cue.deviceID)"])
            }
        }
    }

    private func makeSetlistDocument() -> JBTSetlistFile {
        let songID = "song_001"
        let songTitle = selectedAudioFileName == "No audio loaded" ? "Untitled Song" : selectedAudioFileName
        let songCues: [JBTSetlistFile.Cue] = cues.compactMap { cue in
            guard let lane = lanes.first(where: { $0.id == cue.laneID }) else { return nil }
            let beatIndex = max(0, Int(round(cue.time / beatDuration)))
            let bar = (beatIndex / 4) + 1
            let beat = (beatIndex % 4) + 1

            var endBar: Int?
            var endBeat: Int?
            var endTimeSeconds: Double?
            if let cueEnd = cue.endTime {
                let endBeatIndex = max(0, Int(round(cueEnd / beatDuration)))
                endBar = (endBeatIndex / 4) + 1
                endBeat = (endBeatIndex % 4) + 1
                endTimeSeconds = cueEnd
            }

            return JBTSetlistFile.Cue(
                id: cue.id.uuidString,
                type: cue.kind.rawValue,
                bar: bar,
                beat: beat,
                endBar: endBar,
                endBeat: endBeat,
                timeSeconds: cue.time,
                endTimeSeconds: endTimeSeconds,
                deviceID: lane.target,
                action: cue.actionID,
                params: cue.params,
                startParams: cue.startParams,
                endParams: cue.endParams,
                muted: cue.muted,
                label: cue.label,
                color: lane.accentHex,
                interpolation: cue.kind == .range ? cue.interpolation.rawValue : nil
            )
        }

        let song = JBTSetlistFile.Song(
            id: songID,
            title: songTitle,
            audioPath: loadedAudioURL?.path,
            bpm: bpm,
            timeSignature: "4/4",
            cues: songCues,
            transition: JBTSetlistFile.Transition(type: "immediate", transitionCues: [])
        )

        let globalLibrary = libraryTemplates.map {
            JBTSetlistFile.GlobalCue(
                id: $0.id,
                name: $0.name,
                icon: $0.icon,
                action: $0.actionID,
                deviceType: "unknown",
                params: $0.params,
                tags: ["phase2", "library"]
            )
        }

        let laneRows = lanes.map {
            JBTSetlistFile.DeviceLane(
                deviceID: $0.target,
                label: $0.name,
                color: $0.accentHex,
                offlineBehavior: "skip",
                queueTimeoutSeconds: 5
            )
        }

        let payload = JBTSetlistFile.Payload(
            songs: [song],
            globalCueLibrary: globalLibrary,
            deviceLanes: laneRows,
            midiMappings: []
        )

        return JBTSetlistFile(
            jbtType: "daw_setlist",
            version: "1.0",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            name: projectName,
            payload: payload
        )
    }

    private func applySetlist(_ setlist: JBTSetlistFile, sourceURL: URL) {
        stop()
        projectName = setlist.name
        let song = setlist.payload.songs.first
        bpm = song?.bpm ?? 140
        fitZoom()

        lanes = setlist.payload.deviceLanes.map { lane in
            CueLane(
                id: "lane.\(lane.deviceID)",
                name: lane.label,
                target: lane.deviceID,
                status: .offline,
                accentHex: lane.color,
                discoveryHints: discoveryHints(from: "\(lane.label) \(lane.deviceID)")
            )
        }
        if lanes.isEmpty {
            lanes = Self.placeholderLanes
        }

        if let song, let audioPath = song.audioPath,
           let resolvedURL = resolveAudioPath(audioPath, relativeTo: sourceURL.deletingLastPathComponent()),
           resolvedURL.fileExists
        {
            loadAudio(from: resolvedURL)
        } else {
            clearAudioState()
        }

        var restored: [TimelineCue] = []
        for row in song?.cues ?? [] {
            let laneID = lanes.first(where: { $0.target == row.deviceID })?.id ?? lanes.first?.id ?? "lane.unknown"
            let cueTime = row.timeSeconds ?? timeFrom(bar: row.bar, beat: row.beat, beatDuration: beatDuration)
            let cueEnd = row.endTimeSeconds ?? {
                guard let endBar = row.endBar, let endBeat = row.endBeat else { return nil }
                return timeFrom(bar: endBar, beat: endBeat, beatDuration: beatDuration)
            }()
            let uuid = UUID(uuidString: row.id) ?? UUID()
            restored.append(
                TimelineCue(
                    id: uuid,
                    laneID: laneID,
                    time: max(0, cueTime),
                    endTime: cueEnd,
                    label: row.label,
                    muted: row.muted,
                    deviceTarget: row.deviceID,
                    actionID: row.action,
                    params: row.params,
                    startParams: row.startParams,
                    endParams: row.endParams,
                    kind: CueKind(rawValue: row.type) ?? .oneShot,
                    interpolation: CueInterpolation(rawValue: row.interpolation ?? "") ?? .linear
                )
            )
        }
        cues = restored.sorted { $0.time < $1.time }
        clearScheduledDispatchState()
        selectCue(nil)
        refreshLaneStatusesFromNexus()
    }

    private func applyLegacyProject(_ legacy: JBTProjectFile, sourceURL: URL) {
        let song = JBTSetlistFile.Song(
            id: "song_001",
            title: legacy.payload.title,
            audioPath: legacy.payload.audioPath,
            bpm: legacy.payload.bpm,
            timeSignature: legacy.payload.timeSignature,
            cues: legacy.payload.cues.map {
                JBTSetlistFile.Cue(
                    id: $0.id,
                    type: $0.type,
                    bar: $0.bar,
                    beat: $0.beat,
                    endBar: nil,
                    endBeat: nil,
                    timeSeconds: $0.timeSeconds,
                    endTimeSeconds: nil,
                    deviceID: $0.deviceID,
                    action: $0.action,
                    params: $0.params.compactMapValues { Double($0) },
                    startParams: [:],
                    endParams: [:],
                    muted: $0.muted,
                    label: $0.label,
                    color: $0.color,
                    interpolation: nil
                )
            },
            transition: JBTSetlistFile.Transition(type: "immediate", transitionCues: [])
        )
        let setlist = JBTSetlistFile(
            jbtType: "daw_setlist",
            version: "1.0",
            createdAt: legacy.createdAt,
            name: legacy.name,
            payload: JBTSetlistFile.Payload(
                songs: [song],
                globalCueLibrary: [],
                deviceLanes: legacy.payload.deviceLanes.map {
                    JBTSetlistFile.DeviceLane(
                        deviceID: $0.deviceID,
                        label: $0.label,
                        color: $0.color,
                        offlineBehavior: $0.offlineBehavior,
                        queueTimeoutSeconds: $0.queueTimeoutSeconds
                    )
                },
                midiMappings: []
            )
        )
        applySetlist(setlist, sourceURL: sourceURL)
    }

    private func timeFrom(bar: Int, beat: Int, beatDuration: Double) -> Double {
        let clampedBar = max(1, bar)
        let clampedBeat = max(1, min(4, beat))
        let beatIndex = Double((clampedBar - 1) * 4 + (clampedBeat - 1))
        return beatIndex * beatDuration
    }

    private func resolveAudioPath(_ path: String, relativeTo baseDirectory: URL) -> URL? {
        let expanded = NSString(string: path).expandingTildeInPath
        let candidate = URL(fileURLWithPath: expanded)
        if candidate.path.hasPrefix("/") {
            return candidate
        }
        return baseDirectory.appendingPathComponent(expanded)
    }

    private func discoveryHints(from text: String) -> [String] {
        let lowered = text.lowercased()
        let pieces = lowered
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        return Array(Set(pieces + [lowered]))
    }

    private func loadCapabilitiesCache() {
        guard capabilitiesCacheURL.fileExists else { return }
        guard let data = try? Data(contentsOf: capabilitiesCacheURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clients = root["clients"] as? [String: Any]
        else {
            return
        }

        var loadedCapabilities: [String: [String: Any]] = [:]
        var loadedActions: [String: [CueActionDefinition]] = [:]
        var loadedInfo: [String: DeviceCapabilityInfo] = [:]

        for (clientID, rawCaps) in clients {
            guard let capabilities = rawCaps as? [String: Any] else { continue }
            loadedCapabilities[clientID] = capabilities
            let actions = parseActions(from: capabilities)
            loadedActions[clientID] = actions
            loadedInfo[clientID] = summarizeCapabilities(capabilities: capabilities, actions: actions)
        }

        capabilitiesByClient.merge(loadedCapabilities) { _, new in new }
        actionDefinitionsByClient.merge(loadedActions) { _, new in new }
        capabilityInfoByClient.merge(loadedInfo) { _, new in new }
    }

    private func saveCapabilitiesCache() {
        do {
            let clients = capabilitiesByClient.reduce(into: [String: Any]()) { partial, pair in
                partial[pair.key] = pair.value
            }
            let root: [String: Any] = [
                "saved_at": ISO8601DateFormatter().string(from: Date()),
                "clients": clients,
            ]
            guard JSONSerialization.isValidJSONObject(root) else { return }
            try FileManager.default.createDirectory(at: capabilitiesCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: capabilitiesCacheURL, options: .atomic)
        } catch {
            // Cache write is best-effort and should not interrupt UI flow.
        }
    }

    private func startAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveSetlist(to: self?.autosaveURL ?? URL(fileURLWithPath: "/tmp/autosave.jbt"), isAutosave: true)
            }
        }
        if let autosaveTimer {
            RunLoop.main.add(autosaveTimer, forMode: .common)
        }
    }

    private func startCapabilitiesPollingTimer() {
        guard capabilityPollingEnabled else { return }
        capabilitiesPollTimer?.invalidate()
        capabilitiesPollTimer = Timer.scheduledTimer(withTimeInterval: capabilitiesPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestCapabilitiesForOnlineClients(force: true)
                self?.lastCapabilitiesRefreshAt = Date()
            }
        }
        if let capabilitiesPollTimer {
            RunLoop.main.add(capabilitiesPollTimer, forMode: .common)
        }
    }

    private func stopCapabilitiesPollingTimer() {
        capabilitiesPollTimer?.invalidate()
        capabilitiesPollTimer = nil
    }

    private func wireNexusObservers() {
        nexusClient.$isConnected
            .combineLatest(nexusClient.$isConnecting, nexusClient.$connectedClients)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                if !self.nexusClient.isConnected {
                    self.requestedCapabilityTargets.removeAll()
                }
                if self.capabilityBootstrapQueryEnabled {
                    self.requestCapabilitiesForOnlineClients(force: false)
                }
                if self.capabilityPollingEnabled {
                    self.startCapabilitiesPollingTimer()
                } else {
                    self.stopCapabilitiesPollingTimer()
                }
                self.refreshLaneStatusesFromNexus()
            }
            .store(in: &subscriptions)
    }

    private func handleNexusMessage(_ message: NexusMessage) {
        guard message.type == "capabilities.result" else { return }

        let target = (message.payload["target_client_id"]?.anyValue as? String)
            ?? (message.payload["target"]?.anyValue as? String)
            ?? ""
        guard !target.isEmpty else { return }

        let capabilities = message.payload["capabilities"]?.anyValue as? [String: Any] ?? [:]
        capabilitiesByClient[target] = capabilities
        let actions = parseActions(from: capabilities)
        actionDefinitionsByClient[target] = actions
        capabilityInfoByClient[target] = summarizeCapabilities(capabilities: capabilities, actions: actions)
        saveCapabilitiesCache()
        lastCapabilitiesRefreshAt = Date()

        if let index = lanes.firstIndex(where: { $0.target == target }),
           let label = (capabilities["device_label"] as? String)
               ?? (capabilities["label"] as? String)
               ?? ((capabilities["device"] as? [String: Any])?["label"] as? String),
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lanes[index].name = label
        }
    }

    private func requestCapabilitiesForOnlineClients(force: Bool) {
        guard nexusClient.isConnected, !nexusClient.isConnecting else { return }
        for client in nexusClient.connectedClients where client.online {
            guard client.clientId != nexusClient.clientId, client.clientType != "monitor" else { continue }
            if !force, requestedCapabilityTargets.contains(client.clientId) {
                continue
            }
            requestedCapabilityTargets.insert(client.clientId)
            nexusClient.requestCapabilities(of: client.clientId)
        }
    }

    private func refreshLaneStatusesFromNexus() {
        syncLanesWithRegistry()

        for index in lanes.indices {
            let lane = lanes[index]
            if let match = matchingClient(for: lane) {
                lanes[index].target = match.clientId
                lanes[index].status = resolvedStatus(for: match)
            } else if nexusClient.isConnecting {
                lanes[index].status = .connecting
            } else {
                lanes[index].status = .offline
            }
        }
    }

    private func syncLanesWithRegistry() {
        let clients = nexusClient.connectedClients.filter { info in
            info.clientId != nexusClient.clientId && info.clientType != "monitor"
        }
        guard !clients.isEmpty else { return }

        var updated = lanes
        for client in clients {
            let alreadyMatched = updated.contains(where: { laneMatchesClient(lane: $0, client: client) })
            if alreadyMatched {
                continue
            }

            let discoveredLane = CueLane(
                id: "lane.\(client.clientId)",
                name: capabilitiesByClient[client.clientId]?["label"] as? String ?? prettyLabel(for: client.clientId),
                target: client.clientId,
                status: resolvedStatus(for: client),
                accentHex: accentColorHex(for: client),
                discoveryHints: discoveryHints(from: "\(client.clientId) \(client.clientType)")
            )
            updated.append(discoveredLane)
        }
        lanes = updated
    }

    private func matchingClient(for lane: CueLane) -> NexusClientInfo? {
        nexusClient.connectedClients.first { client in
            laneMatchesClient(lane: lane, client: client)
        }
    }

    private func laneMatchesClient(lane: CueLane, client: NexusClientInfo) -> Bool {
        if client.clientId == nexusClient.clientId || client.clientType == "monitor" {
            return false
        }

        let clientID = client.clientId.lowercased()
        let clientType = client.clientType.lowercased()
        if lane.target.lowercased() == clientID {
            return true
        }

        return lane.discoveryHints.contains { hint in
            let normalized = hint.lowercased()
            return clientID.contains(normalized) || clientType.contains(normalized)
        }
    }

    private func resolvedStatus(for client: NexusClientInfo) -> LaneConnectionState {
        if nexusClient.isConnecting {
            return .connecting
        }
        guard nexusClient.isConnected else {
            return .offline
        }
        return client.online ? .online : .offline
    }

    private func accentColorHex(for client: NexusClientInfo) -> String {
        let lookup = "\(client.clientId) \(client.clientType)".lowercased()
        if lookup.contains("mtpx") {
            return "#00FFFF"
        }
        if lookup.contains("dirty") || lookup.contains("mixer") {
            return "#FF6600"
        }
        if lookup.contains("atlas") || lookup.contains("extron") {
            return "#00FF88"
        }
        if lookup.contains("text") {
            return "#AA00FF"
        }
        if lookup.contains("daw") || lookup.contains("glitchboard") {
            return "#FFCC00"
        }
        return "#888888"
    }

    private func capabilityInfo(for lane: CueLane) -> DeviceCapabilityInfo? {
        if let direct = capabilityInfoByClient[lane.target] {
            return direct
        }
        if let matched = capabilityInfoByClient.first(where: { key, _ in
            lane.discoveryHints.contains(where: { key.lowercased().contains($0.lowercased()) })
        })?.value {
            return matched
        }

        if let bootstrap = bootstrapActions(for: lane), !bootstrap.isEmpty {
            return summarizeCapabilities(capabilities: [:], actions: bootstrap)
        }
        return nil
    }

    private func prettyLabel(for clientID: String) -> String {
        clientID
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { chunk in
                chunk.prefix(1).uppercased() + chunk.dropFirst()
            }
            .joined(separator: " ")
    }

    private func summarizeCapabilities(capabilities: [String: Any], actions: [CueActionDefinition]) -> DeviceCapabilityInfo {
        let root: [String: Any] = {
            if let nested = capabilities["capabilities"] as? [String: Any] {
                return nested
            }
            if let payload = capabilities["payload"] as? [String: Any],
               let nested = payload["capabilities"] as? [String: Any]
            {
                return nested
            }
            return capabilities
        }()

        let model = (root["model"] as? String)
            ?? (root["device_model"] as? String)
            ?? ((root["device"] as? [String: Any])?["model"] as? String)
            ?? ((root["device"] as? [String: Any])?["name"] as? String)

        var inputCount = intValue(root["input_count"])
            ?? intValue((root["io"] as? [String: Any])?["inputs"])
            ?? intValue((root["matrix"] as? [String: Any])?["inputs"])
            ?? intValue((root["ports"] as? [String: Any])?["inputs"])
        var outputCount = intValue(root["output_count"])
            ?? intValue((root["io"] as? [String: Any])?["outputs"])
            ?? intValue((root["matrix"] as? [String: Any])?["outputs"])
            ?? intValue((root["ports"] as? [String: Any])?["outputs"])

        if inputCount == nil {
            inputCount = actions
                .flatMap(\.params)
                .filter { $0.key.lowercased().contains("input") && ($0.valueType == .integer || $0.valueType == .bitset) }
                .map {
                    if $0.valueType == .bitset { return $0.bitCount }
                    return Int($0.maxValue.rounded())
                }
                .max()
        }
        if outputCount == nil {
            outputCount = actions
                .flatMap(\.params)
                .filter { $0.key.lowercased().contains("output") && ($0.valueType == .integer || $0.valueType == .bitset) }
                .map {
                    if $0.valueType == .bitset { return $0.bitCount }
                    return Int($0.maxValue.rounded())
                }
                .max()
        }

        return DeviceCapabilityInfo(
            model: model,
            actionCount: actions.count,
            inputCount: inputCount,
            outputCount: outputCount
        )
    }

    private func parseActions(from capabilities: [String: Any]) -> [CueActionDefinition] {
        var actions: [CueActionDefinition] = []
        let root: [String: Any] = {
            if let nested = capabilities["capabilities"] as? [String: Any] {
                return nested
            }
            if let payload = capabilities["payload"] as? [String: Any],
               let nested = payload["capabilities"] as? [String: Any]
            {
                return nested
            }
            return capabilities
        }()

        if let rawActions = root["actions"] as? [[String: Any]] {
            for raw in rawActions {
                let actionID = (raw["id"] as? String) ?? (raw["action"] as? String) ?? (raw["name"] as? String) ?? "action"
                let actionName = (raw["label"] as? String) ?? (raw["name"] as? String) ?? (raw["action"] as? String) ?? actionID
                let params = parseParams(from: raw["params"])
                actions.append(CueActionDefinition(id: actionID, name: actionName, params: params))
            }
        } else if let rawActionMap = root["actions"] as? [String: Any] {
            for (actionID, raw) in rawActionMap {
                let rawObject = raw as? [String: Any]
                let actionName = rawObject?["label"] as? String ?? actionID
                let params = parseParams(from: rawObject?["params"])
                actions.append(CueActionDefinition(id: actionID, name: actionName, params: params))
            }
        }

        if actions.isEmpty, let intents = root["intents"] as? [String] {
            actions = intents.map { CueActionDefinition(id: $0, name: $0, params: []) }
        }

        if actions.isEmpty, let definitions = root["action_definitions"] as? [[String: Any]] {
            for row in definitions {
                let actionID = (row["id"] as? String) ?? (row["name"] as? String) ?? "action"
                let actionName = (row["label"] as? String) ?? actionID
                let params = parseParams(from: row["params"])
                actions.append(CueActionDefinition(id: actionID, name: actionName, params: params))
            }
        }

        if actions.isEmpty {
            return Self.fallbackActions
        }

        return actions
    }

    private func parseParams(from rawParams: Any?) -> [CueParamDefinition] {
        var params: [CueParamDefinition] = []

        if let list = rawParams as? [[String: Any]] {
            for row in list {
                if let definition = parseParamDefinition(keyHint: nil, row: row) {
                    params.append(definition)
                }
            }
            return params.sorted { $0.key < $1.key }
        }

        if let map = rawParams as? [String: Any] {
            for (key, rowRaw) in map {
                let row = (rowRaw as? [String: Any]) ?? [:]
                if let definition = parseParamDefinition(keyHint: key, row: row) {
                    params.append(definition)
                }
            }
        }

        return params.sorted { $0.key < $1.key }
    }

    private func parseParamDefinition(keyHint: String?, row: [String: Any]) -> CueParamDefinition? {
        let key = keyHint
            ?? (row["key"] as? String)
            ?? (row["id"] as? String)
            ?? (row["name"] as? String)
            ?? "value"
        guard !key.isEmpty else { return nil }

        let name = (row["label"] as? String)
            ?? (row["name"] as? String)
            ?? key
        let typeHint = (row["type"] as? String)?.lowercased() ?? ""
        let isBitsetType = typeHint == "bitset"
            || typeHint == "bitmask"
            || typeHint == "mask"
            || key.lowercased().hasSuffix("_mask")
        let options = parseParamOptions(row["options"])
        let range = parseRange(row["range"])
        let isBoolType = typeHint == "bool" || typeHint == "boolean"

        let minValue = range?.0
            ?? doubleValue(row["min"])
            ?? (options.map(\.value).min() ?? (isBoolType ? 0 : 0))
        let maxValue = range?.1
            ?? doubleValue(row["max"])
            ?? (options.map(\.value).max() ?? (isBoolType ? 1 : 255))

        var defaultValue = doubleValue(row["default"])
            ?? doubleValue(row["value"])
            ?? min(max(minValue, 0), maxValue)
        defaultValue = min(max(defaultValue, minValue), maxValue)

        let inferredType: CueParamValueType = {
            if isBoolType { return .boolean }
            if isBitsetType { return .bitset }
            if !options.isEmpty { return .option }
            if typeHint == "float" || typeHint == "double" || typeHint == "decimal" {
                return .decimal
            }
            if !isIntegerLike(minValue) || !isIntegerLike(maxValue) || !isIntegerLike(defaultValue) {
                return .decimal
            }
            return .integer
        }()

        if !options.isEmpty,
           options.contains(where: { $0.value == defaultValue }) == false,
           let closest = options.min(by: { abs($0.value - defaultValue) < abs($1.value - defaultValue) })
        {
            defaultValue = closest.value
        }

        let stepValue: Double = {
            switch inferredType {
            case .boolean, .integer, .option, .bitset: return 1
            case .decimal:
                let span = maxValue - minValue
                if span <= 1 { return 0.01 }
                if span <= 10 { return 0.05 }
                return 0.1
            }
        }()

        let explicitBitCount = intValue(row["bits"]) ?? intValue(row["bit_count"])
        let inferredBitCount: Int = {
            guard inferredType == .bitset else { return 0 }
            if let explicitBitCount {
                return max(1, min(31, explicitBitCount))
            }
            if maxValue > 0 {
                return max(1, min(31, Int(log2(maxValue + 1).rounded(.up))))
            }
            return 16
        }()

        return CueParamDefinition(
            id: key,
            key: key,
            name: name,
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            valueType: inferredType,
            stepValue: stepValue,
            options: options.sorted { $0.value < $1.value },
            bitCount: inferredBitCount
        )
    }

    private func parseParamOptions(_ raw: Any?) -> [CueParamOption] {
        if let options = raw as? [[String: Any]] {
            return options.enumerated().compactMap { index, row in
                let fallbackValue = Double(index)
                let value = doubleValue(row["value"]) ?? doubleValue(row["id"]) ?? fallbackValue
                let label = (row["label"] as? String)
                    ?? (row["name"] as? String)
                    ?? (row["title"] as? String)
                    ?? String(describing: row["value"] ?? row["id"] ?? index)
                return CueParamOption(id: "\(label)_\(index)", label: label, value: value)
            }
        }

        if let map = raw as? [String: Any] {
            return map.enumerated().compactMap { index, pair in
                let value = doubleValue(pair.value) ?? Double(index)
                return CueParamOption(id: "\(pair.key)_\(index)", label: pair.key, value: value)
            }
        }

        if let strings = raw as? [String] {
            return strings.enumerated().map { index, label in
                CueParamOption(id: "\(label)_\(index)", label: label, value: Double(index))
            }
        }

        if let ints = raw as? [Int] {
            return ints.map { value in
                CueParamOption(id: "opt_\(value)", label: "\(value)", value: Double(value))
            }
        }

        if let doubles = raw as? [Double] {
            return doubles.map { value in
                CueParamOption(id: "opt_\(value)", label: "\(value)", value: value)
            }
        }

        if let mixed = raw as? [Any] {
            return mixed.enumerated().compactMap { index, entry in
                if let value = doubleValue(entry) {
                    return CueParamOption(id: "opt_\(index)", label: "\(value)", value: value)
                }
                if let text = entry as? String {
                    return CueParamOption(id: "\(text)_\(index)", label: text, value: Double(index))
                }
                return nil
            }
        }

        return []
    }

    private func isIntegerLike(_ value: Double) -> Bool {
        abs(value.rounded() - value) < 0.00001
    }

    private func parseRange(_ raw: Any?) -> (Double, Double)? {
        if let range = raw as? [Double], range.count >= 2 {
            return (range[0], range[1])
        }
        if let range = raw as? [Int], range.count >= 2 {
            return (Double(range[0]), Double(range[1]))
        }
        if let range = raw as? [NSNumber], range.count >= 2 {
            return (range[0].doubleValue, range[1].doubleValue)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Double: return Int(v.rounded())
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        default: return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as NSNumber: return v.doubleValue
        case let v as Bool: return v ? 1 : 0
        case let v as String where v.lowercased() == "true": return 1
        case let v as String where v.lowercased() == "false": return 0
        case let v as String: return Double(v)
        default: return nil
        }
    }

    nonisolated private static func extractWaveform(url: URL, targetSampleCount: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }

        let sampleStride = max(1, frames / max(targetSampleCount, 1))
        var output: [Float] = []
        output.reserveCapacity(targetSampleCount)

        var index = 0
        while index < frames {
            let end = min(frames, index + sampleStride)
            var peak: Float = 0

            for frame in index ..< end {
                var mono: Float = 0
                for channel in 0 ..< channels {
                    mono += abs(channelData[channel][frame])
                }
                mono /= Float(channels)
                peak = max(peak, mono)
            }

            output.append(min(1, peak))
            index = end
        }

        return output
    }
}

private extension URL {
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
