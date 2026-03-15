import JoebotSDK
import SwiftUI
import UniformTypeIdentifiers

struct GlitchBoardMainView: View {
    @ObservedObject var state: GlitchBoardState
    @State private var isAudioImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controlStrip

            HStack(alignment: .top, spacing: 12) {
                CueLibraryPanel(state: state)
                    .frame(width: 220)

                timelinePanel
                    .frame(maxWidth: .infinity)

                CueEditorPanel(state: state)
                    .frame(width: 320)
            }

            statusStrip
        }
        .padding(16)
        .background(GlitchBoardTheme.background.ignoresSafeArea())
        .tint(GlitchBoardTheme.accent)
        .fileImporter(isPresented: $isAudioImporterPresented, allowedContentTypes: [.audio]) { result in
            switch result {
            case let .success(url):
                state.loadAudio(from: url)
            case let .failure(error):
                state.statusText = "File import failed: \(error.localizedDescription)"
            }
        }
        .onDeleteCommand {
            state.deleteSelectedCue()
        }
        .alert("Recover Autosave?", isPresented: $state.showAutosaveRecoveryAlert) {
            Button("Recover") {
                state.recoverAutosave()
            }
            Button("Discard", role: .destructive) {
                state.discardAutosave()
            }
        } message: {
            Text("Found autosave at ~/JBT/glitchboard/autosave.jbt")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                Button {
                    state.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In")

                Button("Fit") {
                    state.fitZoom()
                }
                .help("Fit to Song")

                Divider()

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Button("Load Audio") {
                isAudioImporterPresented = true
            }
            .buttonStyle(.borderedProminent)

            Button("Load JBT") {
                state.promptLoadProject()
            }

            Button("Save JBT") {
                state.promptSaveProject()
            }

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

            Divider()
                .frame(height: 22)

            Text(state.activeProjectName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
        GeometryReader { proxy in
            let viewportWidth = max(1, proxy.size.width - 24)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 8) {
                    BarBeatRulerView(state: state, contentWidth: state.timelineContentWidth)
                    WaveformView(state: state, contentWidth: state.timelineContentWidth)

                    ForEach(state.lanes) { lane in
                        CueLaneRowView(state: state, lane: lane, contentWidth: state.timelineContentWidth)
                    }
                }
                .frame(width: state.timelineContentWidth, alignment: .leading)
                .padding(12)
            }
            .onAppear {
                state.setTimelineViewportWidth(viewportWidth)
            }
            .onChange(of: viewportWidth) { _, newWidth in
                state.setTimelineViewportWidth(newWidth)
            }
        }
        .frame(minHeight: 660)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Text("Snap:")
                .foregroundStyle(.secondary)
            Text("1/4 Note")
                .font(.system(.callout, design: .monospaced))

            Divider()
                .frame(height: 16)

            Text("Pos:")
                .foregroundStyle(.secondary)
            Text(state.currentSongPositionString)
                .font(.system(.callout, design: .monospaced))

            Divider()
                .frame(height: 16)

            Text("Total Cues:")
                .foregroundStyle(.secondary)
            Text("\(state.totalCueCount)")
                .font(.system(.callout, design: .monospaced))

            Divider()
                .frame(height: 16)

            Text("Selected:")
                .foregroundStyle(.secondary)
            Text(state.selectedCueSummary)
                .lineLimit(1)
                .truncationMode(.tail)

            Divider()
                .frame(height: 16)

            Text("Label:")
                .foregroundStyle(.secondary)
            TextField("Cue", text: selectedCueLabelBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .disabled(state.selectedCue == nil)

            Spacer()

            Text(state.songProgressDetail())
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 16)

            Text(state.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var selectedCueLabelBinding: Binding<String> {
        Binding(
            get: { state.selectedCueLabelDraft },
            set: { state.updateSelectedCueLabel($0) }
        )
    }
}

private struct CueLibraryPanel: View {
    @ObservedObject var state: GlitchBoardState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cue Library")
                .font(.headline)
            Text("Drag onto a lane")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(state.libraryTemplates) { cue in
                HStack(spacing: 8) {
                    Text(cue.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cue.name)
                            .font(.system(.callout, design: .monospaced))
                        Text(cue.actionID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(GlitchBoardTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onDrag {
                    NSItemProvider(object: cue.id as NSString)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct CueEditorPanel: View {
    @ObservedObject var state: GlitchBoardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cue Editor")
                .font(.headline)

            if let selectedCue = state.selectedCue {
                cueEditorContent(selectedCue: selectedCue)
            } else {
                Text("Select a cue to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(GlitchBoardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GlitchBoardTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cueEditorContent(selectedCue: TimelineCue) -> some View {
        let laneOptions = state.lanes
        let actionOptions = state.availableActions(for: selectedCue.laneID)
        let action = state.actionDefinition(for: selectedCue.laneID, actionID: selectedCue.actionID) ?? actionOptions.first

        Picker("Device", selection: Binding(get: { selectedCue.laneID }, set: { state.updateSelectedCueLane($0) })) {
            ForEach(laneOptions) { lane in
                Text(lane.name).tag(lane.id)
            }
        }

        Picker("Action", selection: Binding(get: { selectedCue.actionID }, set: { state.updateSelectedCueAction($0) })) {
            ForEach(actionOptions) { action in
                Text(action.name).tag(action.id)
            }
        }

        Toggle("Muted", isOn: Binding(get: { selectedCue.muted }, set: { _ in state.toggleMute(selectedCue.id) }))

        if let action {
            Text("Params")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)

            ForEach(action.params) { param in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(param.name) [\(Int(param.minValue))...\(Int(param.maxValue))]")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if selectedCue.kind == .range {
                        HStack {
                            Text("S")
                                .font(.caption2)
                            TextField(
                                "",
                                value: Binding(
                                    get: { selectedCue.startParams[param.key] ?? param.defaultValue },
                                    set: { state.updateSelectedRangeParam(key: param.key, startValue: $0, endValue: selectedCue.endParams[param.key] ?? param.defaultValue) }
                                ),
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            Text("E")
                                .font(.caption2)
                            TextField(
                                "",
                                value: Binding(
                                    get: { selectedCue.endParams[param.key] ?? param.defaultValue },
                                    set: { state.updateSelectedRangeParam(key: param.key, startValue: selectedCue.startParams[param.key] ?? param.defaultValue, endValue: $0) }
                                ),
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        TextField(
                            "",
                            value: Binding(
                                get: { selectedCue.params[param.key] ?? param.defaultValue },
                                set: { state.updateSelectedCueParam(key: param.key, value: $0) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }

        if selectedCue.kind == .range {
            HStack {
                Text("Interpolation")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(get: { selectedCue.interpolation }, set: { state.updateSelectedCueInterpolation($0) })) {
                    Text("linear").tag(CueInterpolation.linear)
                    Text("step").tag(CueInterpolation.step)
                    Text("triangle").tag(CueInterpolation.triangle)
                }
                .labelsHidden()
            }
        }

        HStack {
            Button("Duplicate") {
                state.duplicateCue(selectedCue.id)
            }
            Button("Delete", role: .destructive) {
                state.deleteCue(selectedCue.id)
            }
        }
    }
}

private struct TrackGridOverlayView: View {
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
                    lineWidth: isBar ? 1.1 : 0.6
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
    let contentWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard state.audioDuration > 0 else {
                context.draw(
                    Text("Load audio to display bars and beats")
                        .font(.caption)
                        .foregroundColor(.secondary),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
                return
            }

            let beatCount = max(1, Int(ceil(state.audioDuration / state.beatDuration)))
            let totalBars = max(1, Int(ceil(Double(beatCount) / 4)))

            for beat in 0 ... beatCount {
                let x = CGFloat(Double(beat) * state.beatDuration / state.audioDuration) * size.width
                let beatInBar = beat % 4
                let isBarStart = beatInBar == 0

                var gridPath = Path()
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    gridPath,
                    with: .color(isBarStart ? GlitchBoardTheme.gridMajor : GlitchBoardTheme.gridMinor),
                    lineWidth: isBarStart ? 1.2 : 0.6
                )

                if !isBarStart {
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: x, y: 19))
                    tickPath.addLine(to: CGPoint(x: x, y: 31))
                    context.stroke(tickPath, with: .color(Color.white.opacity(0.45)), lineWidth: 1)
                }
            }

            for bar in 0 ..< totalBars {
                let beatIndex = Double(bar * 4)
                let x = CGFloat((beatIndex * state.beatDuration) / state.audioDuration) * size.width
                context.draw(
                    Text("\(bar + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary),
                    at: CGPoint(x: x + 6, y: 9),
                    anchor: .topLeading
                )
            }

            let playheadX = CGFloat(state.playheadTime / state.audioDuration) * size.width
            var playheadPath = Path()
            playheadPath.move(to: CGPoint(x: playheadX, y: 0))
            playheadPath.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(playheadPath, with: .color(GlitchBoardTheme.accent), lineWidth: 2)
        }
        .frame(width: contentWidth, height: 54)
        .background(GlitchBoardTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WaveformView: View {
    @ObservedObject var state: GlitchBoardState
    let contentWidth: CGFloat

    var body: some View {
        ZStack {
            GlitchBoardTheme.elevatedSurface
            TrackGridOverlayView(
                duration: state.audioDuration,
                beatDuration: state.beatDuration,
                playheadTime: state.playheadTime
            )

            Canvas { context, size in
                guard !state.waveform.isEmpty else {
                    context.draw(
                        Text("Waveform appears here").font(.caption).foregroundColor(.secondary),
                        at: CGPoint(x: size.width / 2, y: size.height / 2)
                    )
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
        .frame(width: contentWidth, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CueLaneRowView: View {
    @ObservedObject var state: GlitchBoardState
    let lane: CueLane
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(lane.name)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(laneAccentColor)
                Spacer()
                Text("\(state.cueCount(for: lane.id)) cues")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    state.clearCues(for: lane.id)
                }
                .font(.caption)
                .disabled(state.cueCount(for: lane.id) == 0)
            }

            GeometryReader { proxy in
                ZStack {
                    GlitchBoardTheme.elevatedSurface

                    TrackGridOverlayView(
                        duration: state.audioDuration,
                        beatDuration: state.beatDuration,
                        playheadTime: state.playheadTime
                    )

                    ForEach(state.cues(for: lane.id)) { cue in
                        cueView(cue: cue, width: proxy.size.width)
                    }
                }
                .coordinateSpace(name: "laneCanvas")
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    state.handleLaneTap(laneID: lane.id, xPosition: location.x, laneWidth: proxy.size.width)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onEnded { value in
                            state.createRangeCue(
                                in: lane.id,
                                startX: value.startLocation.x,
                                endX: value.location.x,
                                laneWidth: proxy.size.width
                            )
                        }
                )
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: CueLibraryDropDelegate(
                        state: state,
                        laneID: lane.id,
                        laneWidth: proxy.size.width
                    )
                )
            }
            .frame(width: contentWidth, height: 106)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(laneAccentColor.opacity(0.28), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func cueView(cue: TimelineCue, width: CGFloat) -> some View {
        if cue.kind == .range, let endTime = cue.endTime {
            let x1 = state.xPosition(for: cue.time, width: width)
            let x2 = state.xPosition(for: endTime, width: width)
            let y: CGFloat = 34

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: x1, y: y))
                    path.addLine(to: CGPoint(x: x2, y: y))
                }
                .stroke(
                    cue.muted ? Color.gray : laneAccentColor,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .onTapGesture(count: 2) {
                    state.cycleInterpolation(for: cue.id)
                }
                .onTapGesture {
                    state.selectCue(cue.id)
                }

                Circle()
                    .fill(cue.muted ? Color.gray : laneAccentColor)
                    .frame(width: 10, height: 10)
                    .position(x: x1, y: y)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("laneCanvas"))
                            .onChanged { value in
                                state.updateCueBoundary(cueID: cue.id, isStart: true, xPosition: value.location.x, laneWidth: width)
                            }
                    )

                Circle()
                    .fill(cue.muted ? Color.gray : laneAccentColor)
                    .frame(width: 10, height: 10)
                    .position(x: x2, y: y)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("laneCanvas"))
                            .onChanged { value in
                                state.updateCueBoundary(cueID: cue.id, isStart: false, xPosition: value.location.x, laneWidth: width)
                            }
                    )

                Text(cue.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .position(x: (x1 + x2) / 2, y: y + 18)
            }
            .contextMenu {
                Button("Edit") { state.selectCue(cue.id) }
                Button(cue.muted ? "Unmute" : "Mute") { state.toggleMute(cue.id) }
                Button("Duplicate") { state.duplicateCue(cue.id) }
                Button("Delete", role: .destructive) { state.deleteCue(cue.id) }
            }
            .help(state.cueTooltip(cue))
        } else {
            let x = state.xPosition(for: cue.time, width: width)
            let isSelected = cue.id == state.selectedCueID

            VStack(spacing: 4) {
                Circle()
                    .fill(cue.muted ? Color.gray : laneAccentColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 1.3)
                    )
                Text(cue.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .lineLimit(1)
            }
            .position(x: min(max(8, x), max(8, width - 8)), y: 30)
            .onTapGesture {
                state.selectCue(cue.id)
            }
            .contextMenu {
                Button("Edit") { state.selectCue(cue.id) }
                Button(cue.muted ? "Unmute" : "Mute") { state.toggleMute(cue.id) }
                Button("Duplicate") { state.duplicateCue(cue.id) }
                Button("Delete", role: .destructive) { state.deleteCue(cue.id) }
            }
            .help(state.cueTooltip(cue))
        }
    }

    private var laneAccentColor: Color {
        Color(hex: lane.accentHex)
    }

    private var statusColor: Color {
        switch lane.status {
        case .online: return .green
        case .offline: return .red
        case .connecting: return .yellow
        }
    }
}

private struct CueLibraryDropDelegate: DropDelegate {
    let state: GlitchBoardState
    let laneID: String
    let laneWidth: CGFloat

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let dropX = info.location.x
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let templateID: String?
            switch item {
            case let value as Data:
                templateID = String(data: value, encoding: .utf8)
            case let value as String:
                templateID = value
            case let value as NSString:
                templateID = value as String
            default:
                templateID = nil
            }
            guard let templateID else { return }
            Task { @MainActor in
                state.dropLibraryCue(templateID: templateID, laneID: laneID, xPosition: dropX, laneWidth: laneWidth)
            }
        }
        return true
    }
}

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
