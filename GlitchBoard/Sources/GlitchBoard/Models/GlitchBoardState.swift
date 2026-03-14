import AVFoundation
import Combine
import Foundation
import JoebotSDK

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
    @Published var lanes: [CueLane] = [
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

    let nexusClient: NexusClient

    private var audioPlayer: AVAudioPlayer?
    private var playheadTimer: Timer?
    private var firedCueIDs: Set<UUID> = []
    private var subscriptions: Set<AnyCancellable> = []

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
                "lane_targets": self.lanes.map(\.target)
            ]
        }

        nexusClient.currentStateProvider = { [weak self] in
            guard let self else { return [:] }
            return [
                "song": self.selectedAudioFileName,
                "bpm": self.bpm,
                "cue_count": self.cues.count,
                "lane_count": self.lanes.count
            ]
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
        let laneName = lanes.first(where: { $0.id == selectedCue.laneID })?.name ?? "Unknown"
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

    func loadAudio(from url: URL) {
        stop()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player

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
            waveform = []
            audioDuration = 0
            selectedAudioFileName = "No audio loaded"
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

    private func wireNexusObservers() {
        nexusClient.$isConnected
            .combineLatest(nexusClient.$isConnecting, nexusClient.$connectedClients)
            .sink { [weak self] _, _, _ in
                self?.refreshLaneStatusesFromNexus()
            }
            .store(in: &subscriptions)
    }

    private func refreshLaneStatusesFromNexus() {
        let connectedClients = nexusClient.connectedClients
        for index in lanes.indices {
            let lane = lanes[index]
            lanes[index].status = resolvedLaneStatus(for: lane, connectedClients: connectedClients)
        }
    }

    private func resolvedLaneStatus(for lane: CueLane, connectedClients: [NexusClientInfo]) -> LaneConnectionState {
        if nexusClient.isConnecting {
            return .connecting
        }
        guard nexusClient.isConnected else {
            return .offline
        }

        let matches = connectedClients.filter { info in
            let clientID = info.clientId.lowercased()
            let clientType = info.clientType.lowercased()
            return lane.discoveryHints.contains(where: { hint in
                clientID.contains(hint) || clientType.contains(hint)
            })
        }

        guard !matches.isEmpty else {
            return .offline
        }

        return matches.contains(where: \.online) ? .online : .offline
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
                    "bar_beat": barBeatString(for: cue.time)
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
