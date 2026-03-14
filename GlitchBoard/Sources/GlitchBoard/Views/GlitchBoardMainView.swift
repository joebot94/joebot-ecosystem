import JoebotSDK
import SwiftUI
import UniformTypeIdentifiers

struct GlitchBoardMainView: View {
    @ObservedObject var state: GlitchBoardState
    @State private var isImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controlStrip
            timelinePanel
            statusStrip
        }
        .padding(16)
        .background(GlitchBoardTheme.background.ignoresSafeArea())
        .tint(GlitchBoardTheme.accent)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            switch result {
            case let .success(url):
                state.loadAudio(from: url)
            case let .failure(error):
                state.statusText = "File import failed: \(error.localizedDescription)"
            }
        }
        .toolbar {
            ToolbarItemGroup {
                NexusStatusIndicator(client: state.nexusClient)
            }
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Button("Load Audio") {
                isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)

            Button("Play") {
                state.play()
            }
            .disabled(!state.hasAudio)

            Button("Pause") {
                state.pause()
            }
            .disabled(!state.hasAudio || !state.isPlaying)

            Button("Stop") {
                state.stop()
            }
            .disabled(!state.hasAudio)

            Divider()
                .frame(height: 22)

            Text("BPM")
                .foregroundStyle(.secondary)

            Stepper(value: $state.bpm, in: 40 ... 240, step: 1) {
                Text("\(Int(state.bpm))")
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 120)

            Spacer(minLength: 8)

            Text(state.selectedAudioFileName)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            BarBeatRulerView(state: state)
            WaveformView(state: state)
            CueLaneView(state: state)
        }
        .padding(12)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Text("Lane:")
                .foregroundStyle(.secondary)
            Text(state.hardcodedLaneName)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(GlitchBoardTheme.accent)

            Divider()
                .frame(height: 16)

            Text("Snap:")
                .foregroundStyle(.secondary)
            Text("1/4 Note")
                .font(.system(.callout, design: .monospaced))

            Divider()
                .frame(height: 16)

            Text(state.statusText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
            Text(state.barBeatString(for: state.playheadTime))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TimelineGridOverlayView: View {
    let duration: Double
    let beatDuration: Double
    let playheadTime: Double

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let beatCount = max(1, Int(ceil(duration / beatDuration)))

            for beat in 0 ... beatCount {
                let x = CGFloat(Double(beat) * beatDuration / duration) * size.width
                let isBar = beat % 4 == 0

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                context.stroke(
                    path,
                    with: .color(isBar ? GlitchBoardTheme.gridMajor : GlitchBoardTheme.gridMinor),
                    lineWidth: isBar ? 1.2 : 0.7
                )
            }

            let playheadX = CGFloat(playheadTime / duration) * size.width
            var playheadPath = Path()
            playheadPath.move(to: CGPoint(x: playheadX, y: 0))
            playheadPath.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(playheadPath, with: .color(GlitchBoardTheme.accent), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

private struct BarBeatRulerView: View {
    @ObservedObject var state: GlitchBoardState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TimelineGridOverlayView(
                    duration: state.audioDuration,
                    beatDuration: state.beatDuration,
                    playheadTime: state.playheadTime
                )

                barLabels(width: proxy.size.width)
            }
            .background(GlitchBoardTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(height: 48)
    }

    @ViewBuilder
    private func barLabels(width: CGFloat) -> some View {
        if state.audioDuration > 0 {
            let totalBars = max(1, Int(ceil((state.audioDuration / state.beatDuration) / 4)))
            ForEach(1 ... totalBars, id: \.self) { bar in
                let beatIndex = Double((bar - 1) * 4)
                let x = CGFloat((beatIndex * state.beatDuration) / state.audioDuration) * width
                Text("\(bar)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .position(x: min(max(12, x + 12), max(12, width - 12)), y: 12)
            }
        } else {
            Text("Load audio to display bars/beats")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }
}

private struct WaveformView: View {
    @ObservedObject var state: GlitchBoardState

    var body: some View {
        ZStack {
            GlitchBoardTheme.elevatedSurface
            TimelineGridOverlayView(
                duration: state.audioDuration,
                beatDuration: state.beatDuration,
                playheadTime: state.playheadTime
            )

            Canvas { context, size in
                guard !state.waveform.isEmpty else {
                    let text = Text("Waveform appears here").font(.caption).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    return
                }

                let midY = size.height / 2
                let stepX = size.width / CGFloat(max(state.waveform.count - 1, 1))
                var path = Path()

                path.move(to: CGPoint(x: 0, y: midY))

                for index in state.waveform.indices {
                    let magnitude = CGFloat(state.waveform[index]) * (size.height * 0.44)
                    let x = CGFloat(index) * stepX
                    path.addLine(to: CGPoint(x: x, y: midY - magnitude))
                }

                for index in state.waveform.indices.reversed() {
                    let magnitude = CGFloat(state.waveform[index]) * (size.height * 0.44)
                    let x = CGFloat(index) * stepX
                    path.addLine(to: CGPoint(x: x, y: midY + magnitude))
                }

                path.closeSubpath()
                context.fill(path, with: .color(GlitchBoardTheme.waveform.opacity(0.80)))
                context.stroke(path, with: .color(GlitchBoardTheme.waveform), lineWidth: 1)
            }
            .padding(.horizontal, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(height: 240)
    }
}

private struct CueLaneView: View {
    @ObservedObject var state: GlitchBoardState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cue Lane: \(state.hardcodedLaneName)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Cues") {
                    state.clearCues()
                }
                .font(.caption)
                .disabled(state.cues.isEmpty)
            }

            GeometryReader { proxy in
                ZStack {
                    GlitchBoardTheme.elevatedSurface
                    TimelineGridOverlayView(
                        duration: state.audioDuration,
                        beatDuration: state.beatDuration,
                        playheadTime: state.playheadTime
                    )

                    ForEach(state.cues) { cue in
                        cueMarker(
                            cue: cue,
                            width: proxy.size.width
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    guard proxy.size.width > 0 else { return }
                    state.placeCue(at: max(0, min(1, location.x / proxy.size.width)))
                }
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func cueMarker(cue: TimelineCue, width: CGFloat) -> some View {
        let x = state.xPosition(for: cue.time, width: width)

        VStack(spacing: 4) {
            Circle()
                .fill(GlitchBoardTheme.accent)
                .frame(width: 10, height: 10)
            Text(cue.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .position(x: min(max(7, x), max(7, width - 7)), y: 31)
        .help("\(cue.label) • \(state.barBeatString(for: cue.time))")
    }
}
