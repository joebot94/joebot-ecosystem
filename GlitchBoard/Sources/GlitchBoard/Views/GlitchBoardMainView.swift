import Foundation
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

                Button {
                    state.refreshCapabilitiesNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Nexus Capabilities")

                Button {
                    state.toggleCapabilityPolling()
                } label: {
                    Image(systemName: state.capabilityPollingEnabled ? "dot.radiowaves.left.and.right.circle.fill" : "dot.radiowaves.left.and.right")
                }
                .help(state.capabilityPollingEnabled ? "Disable Capability Polling" : "Enable Capability Polling")

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

            Text("Caps Poll:")
                .foregroundStyle(.secondary)
            Text(state.capabilityPollingStatus)
                .font(.system(.callout, design: .monospaced))

            Divider()
                .frame(height: 16)

            Text("Caps Refresh:")
                .foregroundStyle(.secondary)
            Text(state.lastCapabilitiesRefreshLabel)
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
        let resolvedActionID = state.resolvedActionID(for: selectedCue)
        let action = state.actionDefinition(for: selectedCue.laneID, actionID: resolvedActionID) ?? actionOptions.first

        Picker("Device", selection: Binding(get: { selectedCue.laneID }, set: { state.updateSelectedCueLane($0) })) {
            ForEach(laneOptions) { lane in
                Text(lane.name).tag(lane.id)
            }
        }
        .pickerStyle(.menu)

        Picker("Action", selection: Binding(get: { resolvedActionID }, set: { state.updateSelectedCueAction($0) })) {
            ForEach(actionOptions) { action in
                Text(action.name).tag(action.id)
            }
        }
        .pickerStyle(.menu)

        Text("Action Source: \(state.actionSourceLabel(for: selectedCue.laneID))")
            .font(.caption2)
            .foregroundStyle(.secondary)

        Toggle("Muted", isOn: Binding(get: { selectedCue.muted }, set: { state.setCueMute(selectedCue.id, muted: $0) }))

        if let action {
            Text("Params")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)

            ForEach(action.params) { param in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(param.name) [\(paramRangeLabel(param))]")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if selectedCue.kind == .range {
                        HStack {
                            Text("S")
                                .font(.caption2)
                            compactParamControl(
                                param: param,
                                value: Binding(
                                    get: { selectedCue.startParams[param.key] ?? param.defaultValue },
                                    set: { state.updateSelectedRangeParam(key: param.key, startValue: $0, endValue: selectedCue.endParams[param.key] ?? param.defaultValue) }
                                )
                            )
                            Text("E")
                                .font(.caption2)
                            compactParamControl(
                                param: param,
                                value: Binding(
                                    get: { selectedCue.endParams[param.key] ?? param.defaultValue },
                                    set: { state.updateSelectedRangeParam(key: param.key, startValue: selectedCue.startParams[param.key] ?? param.defaultValue, endValue: $0) }
                                )
                            )
                        }
                    } else {
                        fullParamControl(
                            param: param,
                            value: Binding(
                                get: { selectedCue.params[param.key] ?? param.defaultValue },
                                set: { state.updateSelectedCueParam(key: param.key, value: $0) }
                            )
                        )
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

    private func paramRangeLabel(_ param: CueParamDefinition) -> String {
        if param.valueType == .boolean {
            return "false/true"
        }
        if param.valueType == .bitset {
            return "\(max(1, param.bitCount))-bit mask"
        }
        if !param.options.isEmpty {
            return "\(param.options.count) options"
        }
        if param.valueType == .decimal {
            return "\(formatNumber(param.minValue, decimals: 2))...\(formatNumber(param.maxValue, decimals: 2))"
        }
        return "\(Int(param.minValue))...\(Int(param.maxValue))"
    }

    @ViewBuilder
    private func compactParamControl(param: CueParamDefinition, value: Binding<Double>) -> some View {
        switch param.valueType {
        case .boolean:
            Toggle("", isOn: Binding(get: { value.wrappedValue >= 0.5 }, set: { value.wrappedValue = $0 ? 1 : 0 }))
                .labelsHidden()
        case .bitset:
            TextField("", value: value, formatter: numberFormatter(for: param))
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
        case .option where !param.options.isEmpty:
            Picker("", selection: value) {
                ForEach(param.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        default:
            TextField("", value: value, formatter: numberFormatter(for: param))
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
        }
    }

    @ViewBuilder
    private func fullParamControl(param: CueParamDefinition, value: Binding<Double>) -> some View {
        switch param.valueType {
        case .boolean:
            Toggle("", isOn: Binding(get: { value.wrappedValue >= 0.5 }, set: { value.wrappedValue = $0 ? 1 : 0 }))
                .labelsHidden()
        case .bitset:
            bitmaskControl(param: param, value: value)
        case .option where !param.options.isEmpty:
            Picker("", selection: value) {
                ForEach(param.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        default:
            HStack(spacing: 8) {
                Slider(
                    value: value,
                    in: param.minValue ... param.maxValue,
                    step: max(0.001, param.stepValue)
                )
                TextField("", value: value, formatter: numberFormatter(for: param))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 74)
            }
        }
    }

    private func bitmaskControl(param: CueParamDefinition, value: Binding<Double>) -> some View {
        let bitCount = max(1, min(24, param.bitCount))
        let selected = selectedBits(maskValue: value.wrappedValue, bitCount: bitCount)
        let columns = [
            GridItem(.adaptive(minimum: 24, maximum: 28), spacing: 4),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(1 ... bitCount, id: \.self) { index in
                    let isOn = selected.contains(index)
                    Button("\(index)") {
                        value.wrappedValue = toggledMaskValue(
                            currentValue: value.wrappedValue,
                            toggleIndex: index,
                            bitCount: bitCount
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: 24, height: 20)
                    .background(isOn ? GlitchBoardTheme.accent.opacity(0.9) : GlitchBoardTheme.elevatedSurface)
                    .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            Text("Selected: \(selected.isEmpty ? "none" : selected.map(String.init).joined(separator: ", "))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func selectedBits(maskValue: Double, bitCount: Int) -> [Int] {
        let mask = max(0, Int(maskValue.rounded()))
        return (1 ... bitCount).filter { index in
            let bit = 1 << (index - 1)
            return (mask & bit) != 0
        }
    }

    private func toggledMaskValue(currentValue: Double, toggleIndex: Int, bitCount: Int) -> Double {
        let clampedIndex = max(1, min(bitCount, toggleIndex))
        var mask = max(0, Int(currentValue.rounded()))
        let bit = 1 << (clampedIndex - 1)
        mask ^= bit
        let maxMask = (1 << bitCount) - 1
        mask = max(0, min(maxMask, mask))
        return Double(mask)
    }

    private func numberFormatter(for param: CueParamDefinition) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = param.valueType == .decimal ? 3 : 0
        return formatter
    }

    private func formatNumber(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}

private struct TrackGridOverlayView: View {
    let duration: Double
    let beatDuration: Double

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
        }
        .allowsHitTesting(false)
    }
}

private struct PlayheadOverlayView: View {
    let duration: Double
    let playheadTime: Double

    var body: some View {
        GeometryReader { proxy in
            if duration > 0 {
                Rectangle()
                    .fill(GlitchBoardTheme.accent)
                    .frame(width: 2, height: proxy.size.height)
                    .position(
                        x: min(max(0, CGFloat(playheadTime / duration) * proxy.size.width), proxy.size.width),
                        y: proxy.size.height / 2
                    )
            }
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
                let barStartBeat = Double(bar * 4)
                let barEndBeat = min(Double((bar + 1) * 4), Double(beatCount))
                let xStart = CGFloat((barStartBeat * state.beatDuration) / state.audioDuration) * size.width
                let xEnd = CGFloat((barEndBeat * state.beatDuration) / state.audioDuration) * size.width
                let xCenter = (xStart + xEnd) * 0.5
                context.draw(
                    Text("\(bar + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary),
                    at: CGPoint(x: xCenter, y: 9),
                    anchor: .top
                )
            }
        }
        .frame(width: contentWidth, height: 54)
        .background(GlitchBoardTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            PlayheadOverlayView(duration: state.audioDuration, playheadTime: state.playheadTime)
        )
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
                beatDuration: state.beatDuration
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
        .overlay(
            PlayheadOverlayView(duration: state.audioDuration, playheadTime: state.playheadTime)
        )
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

            Text(state.laneCapabilitySummary(for: lane.id))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack {
                    GlitchBoardTheme.elevatedSurface

                    TrackGridOverlayView(
                        duration: state.audioDuration,
                        beatDuration: state.beatDuration
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
            .overlay(
                PlayheadOverlayView(duration: state.audioDuration, playheadTime: state.playheadTime)
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
