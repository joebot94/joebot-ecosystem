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

    let nexusClient: NexusClient

    private var audioPlayer: AVAudioPlayer?
    private var loadedAudioURL: URL?
    private var playheadTimer: Timer?
    private var firedCueIDs: Set<UUID> = []
    private var subscriptions: Set<AnyCancellable> = []
    private var requestedCapabilityTargets: Set<String> = []
    private var capabilitiesByClient: [String: [String: Any]] = [:]

    private static let placeholderLanes: [CueLane] = [
        CueLane(
            id: "lane.dirty_mixer",
            name: "Dirty Mixer",
            target: "device.dirty_mixer.1",
            status: .offline,
            accentHex: "#FF6600",
            discoveryHints: ["dirtymixer", "dirty_mixer"]
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
        )
    ]

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

        wireNexusObservers()
        refreshLaneStatusesFromNexus()
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
        guard let selectedCue else { return "None" }
        let laneName = lanes.first(where: { $0.id == selectedCue.laneID })?.name ?? "Unknown Lane"
        return "\(selectedCue.label) • \(laneName) • \(barBeatString(for: selectedCue.time))"
    }

    var timelineContentWidth: CGFloat {
        max(timelineViewportWidth, timelineViewportWidth * zoomScale)
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

    func promptSaveProject() {
        let panel = NSSavePanel()
        panel.title = "Save GlitchBoard Project"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "jbt") ?? .json, .json]
        panel.nameFieldStringValue = "\(safeProjectFileName()).jbt"

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        let destination = chosenURL.pathExtension.isEmpty
            ? chosenURL.appendingPathExtension("jbt")
            : chosenURL
        saveProject(to: destination)
    }

    func promptLoadProject() {
        let panel = NSOpenPanel()
        panel.title = "Open GlitchBoard Project"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jbt") ?? .json, .json]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        loadProject(from: sourceURL)
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
            firedCueIDs.removeAll()
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
            firedCueIDs.removeAll()
        }

        guard !audioPlayer.isPlaying else { return }
        audioPlayer.play()
        isPlaying = true
        startPlayheadTimer()
        statusText = "Playing \(selectedAudioFileName)"
    }

    func pause() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        audioPlayer.pause()
        isPlaying = false
        stopPlayheadTimer()
        statusText = "Paused"
    }

    func stop() {
        if let audioPlayer {
            audioPlayer.stop()
            audioPlayer.currentTime = 0
        }
        isPlaying = false
        playheadTime = 0
        firedCueIDs.removeAll()
        stopPlayheadTimer()
        statusText = "Stopped"
    }

    func clearCues(for laneID: String) {
        cues.removeAll { $0.laneID == laneID }
        if let selectedCueID, cues.contains(where: { $0.id == selectedCueID }) == false {
            selectCue(nil)
        }
        firedCueIDs = firedCueIDs.intersection(Set(cues.map(\.id)))
        statusText = "Cleared cues for \(laneName(for: laneID))"
    }

    func selectCue(_ cueID: UUID?) {
        selectedCueID = cueID
        if let cueID, let cue = cues.first(where: { $0.id == cueID }) {
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
        let hadCue = cues.contains { $0.id == selectedCueID }
        cues.removeAll { $0.id == selectedCueID }
        if hadCue {
            firedCueIDs.remove(selectedCueID)
            selectCue(nil)
            statusText = "Deleted selected cue"
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

        placeCue(in: laneID, at: normalized)
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

    private func placeCue(in laneID: String, at normalizedPosition: CGFloat) {
        let unclamped = Double(normalizedPosition) * audioDuration
        let snappedTime = snapToQuarterNote(unclamped)
        let cue = TimelineCue(laneID: laneID, time: snappedTime)
        cues.append(cue)
        cues.sort { $0.time < $1.time }
        selectCue(cue.id)
        statusText = "Placed \(cue.label) at \(barBeatString(for: snappedTime))"
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

    private func updatePlayhead() {
        guard let audioPlayer else { return }
        let previous = playheadTime
        let current = min(audioDuration, audioPlayer.currentTime)
        playheadTime = current
        fireCrossedCues(startTime: previous, endTime: current)

        if !audioPlayer.isPlaying, current >= audioDuration - 0.001 {
            isPlaying = false
            stopPlayheadTimer()
            statusText = "Stopped"
        }
    }

    private func fireCrossedCues(startTime: Double, endTime: Double) {
        guard endTime >= startTime else { return }

        for cue in cues where cue.time >= startTime && cue.time < endTime {
            guard !firedCueIDs.contains(cue.id) else { continue }
            guard let lane = lanes.first(where: { $0.id == cue.laneID }) else { continue }
            firedCueIDs.insert(cue.id)

            nexusClient.sendIntent(
                targets: [lane.target],
                action: "glitchboard.cue.trigger",
                params: [
                    "cue_id": cue.id.uuidString,
                    "label": cue.label,
                    "lane": lane.name,
                    "bar_beat": barBeatString(for: cue.time),
                ]
            )

            statusText = "Fired \(cue.label) on \(lane.name)"
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
            return "glitchboard_project"
        }
        return base.replacingOccurrences(of: "/", with: "-")
    }

    private func saveProject(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let project = makeProjectDocument()
            let data = try encoder.encode(project)
            try data.write(to: url, options: .atomic)
            activeProjectName = url.lastPathComponent
            statusText = "Saved project to \(url.lastPathComponent)"
        } catch {
            statusText = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadProject(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let document = try decoder.decode(JBTProjectFile.self, from: data)
            applyProjectDocument(document, sourceURL: url)
            activeProjectName = url.lastPathComponent
            statusText = "Loaded project \(url.lastPathComponent)"
        } catch {
            statusText = "Load failed: \(error.localizedDescription)"
        }
    }

    private func makeProjectDocument() -> JBTProjectFile {
        let cuesForFile: [JBTProjectFile.Cue] = cues.compactMap { cue in
            guard let lane = lanes.first(where: { $0.id == cue.laneID }) else { return nil }
            let beatIndex = max(0, Int(round(cue.time / beatDuration)))
            let bar = (beatIndex / 4) + 1
            let beat = (beatIndex % 4) + 1
            return JBTProjectFile.Cue(
                id: cue.id.uuidString,
                type: "one_shot",
                bar: bar,
                beat: beat,
                timeSeconds: cue.time,
                deviceID: lane.target,
                action: "glitchboard.cue.trigger",
                params: ["lane_id": lane.id],
                muted: false,
                label: cue.label,
                color: lane.accentHex
            )
        }

        let laneRows = lanes.map { lane in
            JBTProjectFile.DeviceLane(
                deviceID: lane.target,
                label: lane.name,
                color: lane.accentHex,
                offlineBehavior: "skip",
                queueTimeoutSeconds: 5
            )
        }

        let songTitle = selectedAudioFileName == "No audio loaded"
            ? "Untitled Song"
            : selectedAudioFileName

        let payload = JBTProjectFile.Payload(
            title: songTitle,
            audioPath: loadedAudioURL?.path,
            bpm: bpm,
            timeSignature: "4/4",
            cues: cuesForFile,
            deviceLanes: laneRows
        )

        return JBTProjectFile(
            jbtType: "daw_project",
            version: "1.0",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            name: projectName,
            payload: payload
        )
    }

    private func applyProjectDocument(_ document: JBTProjectFile, sourceURL: URL) {
        stop()
        projectName = document.name
        bpm = document.payload.bpm
        fitZoom()

        lanes = document.payload.deviceLanes.map { lane in
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

        if let audioPath = document.payload.audioPath,
           let resolvedURL = resolveAudioPath(audioPath, relativeTo: sourceURL.deletingLastPathComponent()),
           FileManager.default.fileExists(atPath: resolvedURL.path)
        {
            loadAudio(from: resolvedURL)
        } else {
            clearAudioState()
        }

        var restoredCues: [TimelineCue] = []
        for row in document.payload.cues {
            let cueLaneID = lanes.first(where: { $0.target == row.deviceID })?.id ?? lanes.first?.id ?? "lane.unknown"
            let cueTime = row.timeSeconds ?? timeFrom(bar: row.bar, beat: row.beat, beatDuration: beatDuration)
            guard cueTime.isFinite else { continue }
            let uuid = UUID(uuidString: row.id) ?? UUID()
            restoredCues.append(TimelineCue(id: uuid, laneID: cueLaneID, time: max(0, cueTime), label: row.label))
        }

        cues = restoredCues.sorted { $0.time < $1.time }
        firedCueIDs.removeAll()
        selectCue(nil)
        refreshLaneStatusesFromNexus()
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

    private func wireNexusObservers() {
        nexusClient.$isConnected
            .combineLatest(nexusClient.$isConnecting, nexusClient.$connectedClients)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                if self.nexusClient.isConnected == false {
                    self.requestedCapabilityTargets.removeAll()
                    self.capabilitiesByClient.removeAll()
                }
                self.requestCapabilitiesIfNeeded()
                self.refreshLaneStatusesFromNexus()
            }
            .store(in: &subscriptions)
    }

    private func handleNexusMessage(_ message: NexusMessage) {
        guard message.type == "capabilities.result" else { return }
        guard let target = message.payload["target"]?.anyValue as? String else { return }
        let capabilities = message.payload["capabilities"]?.anyValue as? [String: Any] ?? [:]
        capabilitiesByClient[target] = capabilities

        if let index = lanes.firstIndex(where: { $0.target == target }),
           let label = capabilities["label"] as? String,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lanes[index].name = label
        }
    }

    private func requestCapabilitiesIfNeeded() {
        guard nexusClient.isConnected, !nexusClient.isConnecting else { return }
        for client in nexusClient.connectedClients where client.online {
            guard client.clientId != nexusClient.clientId, client.clientType != "monitor" else { continue }
            if requestedCapabilityTargets.contains(client.clientId) {
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
