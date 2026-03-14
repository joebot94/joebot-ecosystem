import AVFoundation
import Foundation
import JoebotSDK

@MainActor
final class GlitchBoardState: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var bpm: Double = 140
    @Published var audioDuration: Double = 0
    @Published var playheadTime: Double = 0
    @Published var waveform: [Float] = []
    @Published var cues: [TimelineCue] = []
    @Published var selectedAudioFileName = "No audio loaded"
    @Published var statusText = "Load a song to start building cues."
    @Published var isPlaying = false

    let hardcodedLaneName = "Dirty Mixer"
    let hardcodedLaneTarget = "device.dirty_mixer.1"
    let nexusClient: NexusClient

    private var audioPlayer: AVAudioPlayer?
    private var playheadTimer: Timer?
    private var firedCueIDs: Set<UUID> = []

    override init() {
        nexusClient = NexusClient(clientId: "glitchboard_v1", clientType: "daw")
        super.init()

        nexusClient.capabilitiesProvider = {
            [
                "intents": ["glitchboard.cue.trigger"],
                "lane_target": self.hardcodedLaneTarget
            ]
        }

        nexusClient.currentStateProvider = {
            [
                "song": self.selectedAudioFileName,
                "bpm": self.bpm,
                "cue_count": self.cues.count
            ]
        }

        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var beatDuration: Double {
        60 / max(bpm, 1)
    }

    var hasAudio: Bool {
        audioDuration > 0
    }

    func loadAudio(from url: URL) {
        stop()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player

            audioDuration = player.duration
            playheadTime = 0
            selectedAudioFileName = url.lastPathComponent
            firedCueIDs.removeAll()
            statusText = "Loaded \(selectedAudioFileName)"

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
    }

    func clearCues() {
        cues.removeAll()
        firedCueIDs.removeAll()
        statusText = "Cleared cues for \(hardcodedLaneName)"
    }

    func placeCue(at normalizedPosition: CGFloat) {
        guard hasAudio else { return }
        let unclamped = Double(normalizedPosition) * audioDuration
        let snappedTime = snapToQuarterNote(unclamped)
        let cue = TimelineCue(time: snappedTime, label: "Cue \(cues.count + 1)")
        cues.append(cue)
        cues.sort { $0.time < $1.time }
        statusText = "Placed \(cue.label) at \(barBeatString(for: snappedTime))"
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

    private func startPlayheadTimer() {
        stopPlayheadTimer()
        playheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
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
            firedCueIDs.insert(cue.id)

            nexusClient.sendIntent(
                targets: [hardcodedLaneTarget],
                action: "glitchboard.cue.trigger",
                params: [
                    "cue_id": cue.id.uuidString,
                    "label": cue.label,
                    "bar_beat": barBeatString(for: cue.time)
                ]
            )

            statusText = "Fired \(cue.label) on \(hardcodedLaneName)"
        }
    }

    private func snapToQuarterNote(_ time: Double) -> Double {
        let snappedBeatIndex = (time / beatDuration).rounded()
        let snappedTime = snappedBeatIndex * beatDuration
        return min(max(0, snappedTime), audioDuration)
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
