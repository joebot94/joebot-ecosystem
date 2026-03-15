import JoebotSDK
import SwiftUI
import UniformTypeIdentifiers

private enum CatalogThemePreset: String, CaseIterable, Identifiable {
    case dos
    case neon
    case amber

    var id: String { rawValue }

    var windowTitle: String {
        switch self {
        case .dos:
            return "DOS / Win3.11"
        case .neon:
            return "Neon Dark"
        case .amber:
            return "Amber Terminal"
        }
    }

    var theme: CatalogTheme {
        switch self {
        case .dos:
            return CatalogTheme(
                background: Color(red: 0.78, green: 0.78, blue: 0.78),
                panelBackground: Color(red: 0.72, green: 0.72, blue: 0.72),
                panelInner: Color(red: 0.87, green: 0.87, blue: 0.87),
                previewBackground: Color(red: 0.00, green: 0.14, blue: 0.31),
                text: Color(red: 0.04, green: 0.07, blue: 0.11),
                accent: Color(red: 0.00, green: 0.20, blue: 0.78),
                border: Color.black.opacity(0.85),
                selection: Color(red: 0.00, green: 0.24, blue: 0.72),
                muted: Color.black.opacity(0.55),
                strongText: .white
            )
        case .neon:
            return CatalogTheme(
                background: Color(red: 0.08, green: 0.09, blue: 0.10),
                panelBackground: Color(red: 0.07, green: 0.08, blue: 0.09),
                panelInner: Color(red: 0.10, green: 0.11, blue: 0.12),
                previewBackground: Color(red: 0.00, green: 0.14, blue: 0.31),
                text: Color(red: 0.88, green: 0.90, blue: 0.94),
                accent: Color(red: 0.00, green: 0.90, blue: 1.00),
                border: Color.white.opacity(0.22),
                selection: Color(red: 0.10, green: 0.28, blue: 0.43),
                muted: Color.white.opacity(0.45),
                strongText: Color(red: 0.90, green: 0.98, blue: 1.00)
            )
        case .amber:
            return CatalogTheme(
                background: Color(red: 0.11, green: 0.07, blue: 0.04),
                panelBackground: Color(red: 0.14, green: 0.08, blue: 0.03),
                panelInner: Color(red: 0.16, green: 0.09, blue: 0.03),
                previewBackground: Color(red: 0.07, green: 0.04, blue: 0.01),
                text: Color(red: 0.98, green: 0.75, blue: 0.28),
                accent: Color(red: 0.93, green: 0.57, blue: 0.07),
                border: Color(red: 0.68, green: 0.40, blue: 0.07),
                selection: Color(red: 0.45, green: 0.26, blue: 0.05),
                muted: Color(red: 0.84, green: 0.55, blue: 0.17),
                strongText: Color(red: 1.00, green: 0.80, blue: 0.37)
            )
        }
    }
}

private struct CatalogTheme {
    let background: Color
    let panelBackground: Color
    let panelInner: Color
    let previewBackground: Color
    let text: Color
    let accent: Color
    let border: Color
    let selection: Color
    let muted: Color
    let strongText: Color
}

private struct RetroButtonStyle: ButtonStyle {
    let theme: CatalogTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(configuration.isPressed ? theme.selection : theme.panelBackground)
            .overlay(
                Rectangle()
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

private struct RetroPanel<Content: View>: View {
    let title: String
    let theme: CatalogTheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .foregroundStyle(theme.strongText)
                .background(theme.accent)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(6)
        .background(theme.panelBackground)
        .overlay(
            Rectangle()
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

struct MainCatalogView: View {
    @ObservedObject var state: CatalogState

    @State private var preset: CatalogThemePreset = .dos
    @State private var searchText: String = ""
    @State private var selectedKindFilter: String = "All kinds"
    @State private var mediaGridView = false
    @State private var showingNewSessionSheet = false
    @State private var showingEditSessionSheet = false
    @State private var showingDeleteSessionAlert = false
    @State private var showingAddTapeSheet = false
    @State private var showingEditTapeSheet = false
    @State private var showingAddGearSheet = false
    @State private var showingEditGearSheet = false
    @State private var showingMediaImporter = false
    @State private var showingEditMediaSheet = false
    @State private var showingGearPhotoImporter = false
    @State private var showingReplaySheet = false

    private var theme: CatalogTheme { preset.theme }

    private var filteredSessions: [SessionRecord] {
        guard !searchText.isEmpty else { return state.sessions }
        let query = searchText.lowercased()
        return state.sessions.filter { session in
            session.title.lowercased().contains(query)
                || session.location.lowercased().contains(query)
                || session.date.lowercased().contains(query)
                || session.notes.lowercased().contains(query)
                || session.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var kindOptions: [String] {
        let kinds = Set(state.mediaForSelectedSession.map { $0.kind })
        return ["All kinds"] + kinds.sorted()
    }

    private var filteredMedia: [MediaRecord] {
        guard selectedKindFilter != "All kinds" else {
            return state.mediaForSelectedSession
        }
        return state.mediaForSelectedSession.filter { $0.kind == selectedKindFilter }
    }

    private var replayIsAvailable: Bool {
        guard let log = state.eventLog else { return false }
        return ReplayEngine.durationMs(from: log) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if !state.nexusClient.isConnected {
                Text("Nexus Offline")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.strongText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.red.opacity(0.72))
            }

            HStack(spacing: 8) {
                sessionsColumn
                    .frame(width: 330)

                mainGrid
            }
            .padding(8)
        }
        .background(theme.background)
        .foregroundStyle(theme.text)
        .toolbar {
            ToolbarItemGroup {
                Button(state.isSnapshotInFlight ? "Snapshot..." : "Snapshot") {
                    state.sendSnapshot()
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 120)
                .disabled(!state.nexusClient.isConnected || state.isSnapshotInFlight || state.selectedSession == nil)
                .help(state.nexusClient.isConnected ? "Capture a studio snapshot" : "Connect to Nexus to snapshot")

                Button {
                    state.toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isRecordingCurrentSession ? Color.red : Color.gray)
                            .frame(width: 9, height: 9)
                        Text(state.isRecordingCurrentSession ? "Stop" : "Record")
                    }
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 110)
                .disabled(!state.nexusClient.isConnected || state.selectedSession == nil)
                .help(state.nexusClient.isConnected ? "Start/stop recording session events" : "Connect to Nexus to record")

                Picker("Theme", selection: $preset) {
                    ForEach(CatalogThemePreset.allCases) { item in
                        Text(item.windowTitle).tag(item)
                    }
                }
                .frame(width: 170)

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
        .sheet(isPresented: $showingNewSessionSheet) {
            SessionEditorSheet(
                mode: .new,
                initialTitle: "",
                initialDate: Date(),
                initialLocation: "",
                initialNotes: "",
                initialTags: [],
                onSave: { title, date, location, notes, tags in
                    state.createSession(
                        title: title,
                        date: CatalogState.format(date: date),
                        location: location,
                        notes: notes,
                        tags: tags
                    )
                }
            )
        }
        .sheet(isPresented: $showingEditSessionSheet) {
            if let selected = state.selectedSession {
                SessionEditorSheet(
                    mode: .edit,
                    initialTitle: selected.title,
                    initialDate: CatalogState.parse(dateString: selected.date),
                    initialLocation: selected.location,
                    initialNotes: selected.notes,
                    initialTags: selected.tags,
                    onSave: { title, date, location, notes, tags in
                        state.updateSelectedSession(
                            title: title,
                            date: CatalogState.format(date: date),
                            location: location,
                            notes: notes,
                            tags: tags
                        )
                    }
                )
            } else {
                Text("No session selected")
                    .frame(width: 420, height: 220)
            }
        }
        .sheet(isPresented: $showingAddTapeSheet) {
            TapeEditorSheet(
                mode: .new,
                initialTapeID: "",
                initialFormat: "VHS",
                initialLabel: "",
                initialStorageLocation: "",
                initialNotes: "",
                onSave: { tapeID, format, label, storageLocation, notes in
                    state.addTape(
                        tapeID: tapeID,
                        format: format,
                        label: label,
                        storageLocation: storageLocation,
                        notes: notes
                    )
                }
            )
        }
        .sheet(isPresented: $showingEditTapeSheet) {
            if let selected = state.selectedTape {
                TapeEditorSheet(
                    mode: .edit,
                    initialTapeID: selected.tapeID,
                    initialFormat: selected.format,
                    initialLabel: selected.label,
                    initialStorageLocation: selected.storageLocation,
                    initialNotes: selected.notes,
                    onSave: { tapeID, format, label, storageLocation, notes in
                        state.updateSelectedTape(
                            tapeID: tapeID,
                            format: format,
                            label: label,
                            storageLocation: storageLocation,
                            notes: notes
                        )
                    }
                )
            } else {
                Text("No tape selected")
                    .frame(width: 420, height: 220)
            }
        }
        .sheet(isPresented: $showingAddGearSheet) {
            GearEditorSheet(
                mode: .new,
                initialName: "",
                initialNotes: "",
                onSave: { name, notes in
                    state.addGearToSession(name: name, notes: notes)
                }
            )
        }
        .sheet(isPresented: $showingEditGearSheet) {
            if let selected = state.selectedGearRow {
                GearEditorSheet(
                    mode: .edit,
                    initialName: selected.gear.name,
                    initialNotes: selected.link.notes,
                    onSave: { name, notes in
                        state.updateSelectedGear(name: name, notes: notes)
                    }
                )
            } else {
                Text("No gear selected")
                    .frame(width: 420, height: 220)
            }
        }
        .sheet(isPresented: $showingEditMediaSheet) {
            if let selected = state.selectedMedia {
                MediaMetadataSheet(
                    initialKind: selected.kind,
                    initialNotes: selected.notes,
                    initialToolPath: selected.toolPath,
                    initialSettingsNotes: selected.settingsNotes,
                    onSave: { kind, notes, toolPath, settingsNotes in
                        state.updateSelectedMedia(
                            kind: kind,
                            notes: notes,
                            toolPath: toolPath,
                            settingsNotes: settingsNotes
                        )
                    }
                )
            } else {
                Text("No media selected")
                    .frame(width: 420, height: 220)
            }
        }
        .sheet(isPresented: $showingReplaySheet) {
            if let session = state.selectedSession, let log = state.eventLog, ReplayEngine.durationMs(from: log) > 0 {
                ReplaySessionSheet(state: state, session: session, eventLog: log, theme: theme)
            } else {
                VStack(spacing: 10) {
                    Text("No timeline data")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text("This session has no replayable duration yet. Start recording during your next session to enable replay.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(width: 560, height: 220)
            }
        }
        .sheet(item: Binding(
            get: { state.pendingSnapshotDraft },
            set: { state.pendingSnapshotDraft = $0 }
        )) { draft in
            PresetNameSheet(
                defaultName: draft.defaultName,
                onCancel: {
                    state.cancelPendingSnapshot()
                },
                onConfirm: { name in
                    state.confirmPendingSnapshot(name: name)
                }
            )
        }
        .alert("Delete Session?", isPresented: $showingDeleteSessionAlert) {
            Button("Delete", role: .destructive) {
                state.deleteSelectedSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected .jbt session file.")
        }
        .fileImporter(
            isPresented: $showingMediaImporter,
            allowedContentTypes: [.movie, .image, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                state.addMediaFiles(urls: urls)
            case .failure:
                state.selectMedia(nil)
            }
        }
        .fileImporter(
            isPresented: $showingGearPhotoImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                state.attachPhotosToSelectedGear(urls: urls)
            case .failure:
                break
            }
        }
        .onChange(of: kindOptions) { _, next in
            if !next.contains(selectedKindFilter) {
                selectedKindFilter = "All kinds"
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.accent, lineWidth: 1)
                    )
                    .padding(14)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.toastMessage)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Text("Glitch Catalog [\(preset.windowTitle)]")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.muted)
            Spacer()
        }
        .frame(height: 38)
        .background(theme.panelBackground)
        .overlay(
            Rectangle()
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var sessionsColumn: some View {
        RetroPanel(title: "Sessions", theme: theme) {
            VStack(spacing: 6) {
                TextField("Instant search: title, location, tags...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .background(theme.panelInner)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredSessions) { session in
                            Button {
                                state.selectSession(session.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(session.date) - \(session.title) [tags: \(sessionTagsText(session))]")
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(
                                    state.selectedSessionID == session.id ? theme.strongText : theme.text
                                )
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    state.selectedSessionID == session.id ? theme.selection : theme.panelInner
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("New Session") {
                        showingNewSessionSheet = true
                    }
                    .buttonStyle(RetroButtonStyle(theme: theme))

                    Button("Edit Session") {
                        showingEditSessionSheet = true
                    }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .disabled(state.selectedSession == nil)

                    Button("Delete Session") {
                        showingDeleteSessionAlert = true
                    }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .disabled(state.selectedSession == nil)
                }

                Button("Replay") {
                    showingReplaySheet = true
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .disabled(state.selectedSession == nil || !replayIsAvailable)
                .help(!replayIsAvailable
                    ? "No event log — start recording during your next session to enable replay"
                    : "Open session replay")

                presetsSection
                    .frame(height: 180)

                replaysSection
                    .frame(height: 170)
            }
        }
    }

    private var presetsSection: some View {
        RetroPanel(title: "Presets", theme: theme) {
            if state.presets.isEmpty {
                Text("No presets yet")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
                    .background(theme.panelInner)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.presets) { preset in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    state.selectPreset(preset.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .lineLimit(1)
                                        Text(state.prettyTimestamp(preset.createdAt))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                        Text(preset.capturedClients.joined(separator: ", "))
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(5)
                                }
                                .buttonStyle(.plain)
                                .background(state.selectedPresetID == preset.id ? theme.selection : theme.panelInner)
                                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                                HStack(spacing: 6) {
                                    Button("Recall") {
                                        state.recallPreset(preset)
                                    }
                                    .buttonStyle(RetroButtonStyle(theme: theme))
                                    .disabled(!state.nexusClient.isConnected)
                                    .help(state.nexusClient.isConnected ? "Recall this preset" : "Connect to Nexus to recall")

                                    Button("Delete") {
                                        state.deletePreset(preset.id)
                                    }
                                    .buttonStyle(RetroButtonStyle(theme: theme))
                                }
                            }
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
            }
        }
    }

    private var replaysSection: some View {
        RetroPanel(title: "Replays", theme: theme) {
            if state.replays.isEmpty {
                Text("No replays yet")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
                    .background(theme.panelInner)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.replays, id: \.replayID) { replay in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    state.selectReplay(replay.replayID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(replay.sessionName)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .lineLimit(1)
                                        Text(state.prettyTimestamp(replay.startedAt))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                        Text("dur \(state.clockString(from: ReplayEngine.durationMs(from: replay))) • events \(replay.events.count)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(5)
                                }
                                .buttonStyle(.plain)
                                .background(state.selectedReplayID == replay.replayID ? theme.selection : theme.panelInner)
                                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                                HStack(spacing: 6) {
                                    Button("Load") {
                                        state.selectReplay(replay.replayID)
                                    }
                                    .buttonStyle(RetroButtonStyle(theme: theme))

                                    Button("Open") {
                                        state.selectReplay(replay.replayID)
                                        showingReplaySheet = true
                                    }
                                    .buttonStyle(RetroButtonStyle(theme: theme))
                                    .disabled(ReplayEngine.durationMs(from: replay) <= 0)

                                    Button("Delete") {
                                        state.deleteReplay(replay.replayID)
                                    }
                                    .buttonStyle(RetroButtonStyle(theme: theme))
                                }
                            }
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
            }
        }
    }

    private var mainGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tapesPanel
                gearPanel
                mediaPanel
            }

            HStack(spacing: 8) {
                Button("Export Session to JSON") {
                    state.exportSelectedSessionJSON()
                }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 360)
                    .disabled(state.selectedSession == nil)

                Text("Tapes: \(state.tapesForSelectedSession.count) | Gear: \(state.gearChainForSelectedSession.count) | Media: \(filteredMedia.count) | Presets: \(state.presets.count) | Events: \(state.eventLog?.events.count ?? 0)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)

                Button("Export Media CSV") {
                    state.exportSelectedMediaCSV(mediaItems: filteredMedia)
                }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 360)
                    .disabled(state.selectedSession == nil || filteredMedia.isEmpty)
            }

            RetroPanel(title: "Preview", theme: theme) {
                if let preset = state.selectedPreset {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preset: \(preset.name)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.strongText)
                        Text("Captured: \(state.prettyTimestamp(preset.createdAt))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.accent)

                        if !preset.notes.isEmpty {
                            Text(preset.notes)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.muted)
                                .lineLimit(4)
                        }

                        ScrollView {
                            Text(state.presetDetailsText(preset))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.strongText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .background(theme.previewBackground)
                        .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hover/select items to preview. Session summary shown when idle.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.accent)

                        Text(state.selectedSession?.notes ?? "No session selected")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.strongText)
                            .lineLimit(4)

                        if let session = state.selectedSession {
                            Text("Tags: \(sessionTagsText(session))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                        }

                        if let eventLog = state.eventLog {
                            Divider()
                                .overlay(theme.border)

                            Text("Timeline [\(eventLog.sessionName)]")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(eventLog.events.reversed()) { event in
                                        Text("\(state.prettyTimestamp(event.timestamp))  [\(event.type)]  \(event.summary)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .background(theme.previewBackground)
                            .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(6)
                    .background(theme.previewBackground)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var tapesPanel: some View {
        RetroPanel(title: "Analog Masters (Tapes)", theme: theme) {
            VStack(spacing: 6) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(state.tapesForSelectedSession, id: \.id) { tape in
                            Button {
                                state.selectTape(tape.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(tape.tapeID) [\(tape.format)]  \(tape.label)")
                                        .lineLimit(1)
                                    if !tape.storageLocation.isEmpty {
                                        Text(tape.storageLocation)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(state.selectedTapeID == tape.id ? theme.selection : theme.panelInner)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("Add Tape") {
                        showingAddTapeSheet = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedSession == nil)
                    Button("Edit Selected") {
                        showingEditTapeSheet = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedTape == nil)
                    Button("Delete Selected") {
                        state.deleteSelectedTape()
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedTape == nil)
                }
            }
        }
    }

    private var gearPanel: some View {
        RetroPanel(title: "Gear Chain (Session)", theme: theme) {
            VStack(spacing: 6) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.gearRowsForSelectedSession.enumerated()), id: \.element.id) { idx, row in
                            Button {
                                state.selectGearLink(row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(idx + 1). \(row.gear.name)")
                                    if !row.link.notes.isEmpty {
                                        Text(row.link.notes)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                            .lineLimit(1)
                                    }
                                    if !row.link.photos.isEmpty {
                                        Text("photos: \(row.link.photos.count)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(state.selectedGearLinkID == row.id ? theme.selection : theme.panelInner)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("Add Gear...") {
                        showingAddGearSheet = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedSession == nil)
                    Button("Edit Gear...") {
                        showingEditGearSheet = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedGearRow == nil)
                    Button("Add Photos...") {
                        showingGearPhotoImporter = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedGearRow == nil)
                    Button("Open Photo") {
                        state.openSelectedGearPhoto()
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedGearRow?.link.photos.isEmpty ?? true)
                    Button("Remove From Session") {
                        state.removeSelectedGearFromSession()
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedGearRow == nil)
                }
            }
        }
    }

    private var mediaPanel: some View {
        RetroPanel(title: "Digital Files (Captures / Stills / Scripts / References)", theme: theme) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("Kind Filter:")
                        .font(.system(size: 12, design: .monospaced))

                    Picker("Kind", selection: $selectedKindFilter) {
                        ForEach(kindOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    Button(mediaGridView ? "List View" : "Grid View") {
                        mediaGridView.toggle()
                    }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 90)

                    Spacer()
                }

                if mediaGridView {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                            ForEach(filteredMedia) { item in
                                Button {
                                    state.selectMedia(item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.kind.uppercased())
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(theme.accent)
                                        Text(URL(fileURLWithPath: item.filePath).lastPathComponent)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        let details = mediaDetailsText(for: item)
                                        if !details.isEmpty {
                                            Text(details)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(theme.muted)
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                                    .background(state.selectedMediaID == item.id ? theme.selection : theme.panelInner)
                                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                    }
                    .background(theme.panelInner)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredMedia) { item in
                                Button {
                                    state.selectMedia(item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(item.kind): \(item.filePath)")
                                            .lineLimit(1)
                                        if !item.notes.isEmpty {
                                            Text(item.notes)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(theme.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(state.selectedMediaID == item.id ? theme.selection : theme.panelInner)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                    }
                    .background(theme.panelInner)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                }

                HStack(spacing: 6) {
                    Button("Add Media Files...") {
                        showingMediaImporter = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedSession == nil)
                    Button("Edit Metadata...") {
                        showingEditMediaSheet = true
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedMedia == nil)
                    Button("Open Selected") {
                        state.openSelectedMedia()
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedMedia == nil)
                    Button("Delete Selected") {
                        state.deleteSelectedMedia()
                    }
                        .buttonStyle(RetroButtonStyle(theme: theme))
                        .disabled(state.selectedMedia == nil)
                }
            }
        }
    }

    private func sessionTagsText(_ session: SessionRecord) -> String {
        guard !session.tags.isEmpty else { return "-" }
        return session.tags.joined(separator: ", ")
    }

    private func mediaDetailsText(for item: MediaRecord) -> String {
        var bits: [String] = []
        if item.width > 0, item.height > 0 {
            bits.append("\(item.width)x\(item.height)")
        }
        if item.duration > 0 {
            bits.append(String(format: "%.1fs", item.duration))
        }
        if !item.codec.isEmpty {
            bits.append(item.codec)
        }
        return bits.joined(separator: " • ")
    }
}

private enum SessionEditorMode {
    case new
    case edit

    var title: String {
        switch self {
        case .new:
            return "New Session"
        case .edit:
            return "Edit Session"
        }
    }

    var actionLabel: String {
        switch self {
        case .new:
            return "Create"
        case .edit:
            return "Save"
        }
    }
}

private struct SessionEditorSheet: View {
    let mode: SessionEditorMode
    let onSave: (String, Date, String, String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var location: String
    @State private var notes: String
    @State private var tagsText: String

    init(
        mode: SessionEditorMode,
        initialTitle: String,
        initialDate: Date,
        initialLocation: String,
        initialNotes: String,
        initialTags: [String],
        onSave: @escaping (String, Date, String, String, [String]) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
        _location = State(initialValue: initialLocation)
        _notes = State(initialValue: initialNotes)
        _tagsText = State(initialValue: initialTags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.title)
                .font(.headline)

            TextField("Title", text: $title)
            DatePicker("Date", selection: $date, displayedComponents: [.date])
            TextField("Location", text: $location)
            TextField("Tags (comma)", text: $tagsText)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(4 ... 8)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(mode.actionLabel) {
                    let tags = tagsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        date,
                        location,
                        notes,
                        tags
                    )
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}

private enum TapeEditorMode {
    case new
    case edit

    var title: String {
        switch self {
        case .new:
            return "Add Tape"
        case .edit:
            return "Edit Tape"
        }
    }

    var actionLabel: String {
        switch self {
        case .new:
            return "Add"
        case .edit:
            return "Save"
        }
    }
}

private struct TapeEditorSheet: View {
    let mode: TapeEditorMode
    let onSave: (String, String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tapeID: String
    @State private var format: String
    @State private var label: String
    @State private var storageLocation: String
    @State private var notes: String

    init(
        mode: TapeEditorMode,
        initialTapeID: String,
        initialFormat: String,
        initialLabel: String,
        initialStorageLocation: String,
        initialNotes: String,
        onSave: @escaping (String, String, String, String, String) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _tapeID = State(initialValue: initialTapeID)
        _format = State(initialValue: initialFormat)
        _label = State(initialValue: initialLabel)
        _storageLocation = State(initialValue: initialStorageLocation)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.title)
                .font(.headline)

            TextField("Tape ID", text: $tapeID)
            TextField("Format", text: $format)
            TextField("Label", text: $label)
            TextField("Storage Location", text: $storageLocation)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode.actionLabel) {
                    onSave(
                        tapeID.trimmingCharacters(in: .whitespacesAndNewlines),
                        format.trimmingCharacters(in: .whitespacesAndNewlines),
                        label.trimmingCharacters(in: .whitespacesAndNewlines),
                        storageLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}

private enum GearEditorMode {
    case new
    case edit

    var title: String {
        switch self {
        case .new:
            return "Add Gear"
        case .edit:
            return "Edit Gear"
        }
    }

    var actionLabel: String {
        switch self {
        case .new:
            return "Add"
        case .edit:
            return "Save"
        }
    }
}

private struct GearEditorSheet: View {
    let mode: GearEditorMode
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String

    init(
        mode: GearEditorMode,
        initialName: String,
        initialNotes: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.title)
                .font(.headline)

            TextField("Gear Name", text: $name)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode.actionLabel) {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), notes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 260)
    }
}

private struct MediaMetadataSheet: View {
    let onSave: (String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var notes: String
    @State private var toolPath: String
    @State private var settingsNotes: String

    init(
        initialKind: String,
        initialNotes: String,
        initialToolPath: String,
        initialSettingsNotes: String,
        onSave: @escaping (String, String, String, String) -> Void
    ) {
        self.onSave = onSave
        _kind = State(initialValue: initialKind)
        _notes = State(initialValue: initialNotes)
        _toolPath = State(initialValue: initialToolPath)
        _settingsNotes = State(initialValue: initialSettingsNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Media Metadata")
                .font(.headline)

            TextField("Kind (video/image/script/reference)", text: $kind)
            TextField("Tool Path", text: $toolPath)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
            TextField("Settings Notes", text: $settingsNotes, axis: .vertical)
                .lineLimit(3 ... 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(
                        kind.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes,
                        toolPath.trimmingCharacters(in: .whitespacesAndNewlines),
                        settingsNotes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 360)
    }
}

private struct ReplayTimelineEvent: Identifiable {
    let id: String
    let relativeMs: Double
    let entry: EventLogEntry
    let payload: [String: Any]
}

private struct ReplayChannelState: Identifiable, Hashable {
    let id: Int
    let inputA: Bool
    let inputB: Bool
    let mix: Int
}

private struct ReplayMomentState {
    var snapshot: [String: Any]
    var channels: [ReplayChannelState]
    var lastEvent: ReplayTimelineEvent?
    var nextEvent: ReplayTimelineEvent?
}

private enum ReplayEngine {
    static func durationMs(from log: EventLogRecord) -> Double {
        let timelineEvents = timeline(from: log)
        guard let last = timelineEvents.last?.relativeMs, last.isFinite, last > 0 else {
            return 0
        }
        return last
    }

    static func timeline(from log: EventLogRecord) -> [ReplayTimelineEvent] {
        let startEpoch = parseISO(log.startedAt) ?? 0
        let events = log.events.map { entry -> ReplayTimelineEvent in
            let relativeMs = resolvedRelativeMs(for: entry, startEpoch: startEpoch)
            return ReplayTimelineEvent(
                id: "\(entry.id)|\(relativeMs)",
                relativeMs: relativeMs,
                entry: entry,
                payload: entry.payload.mapValues { $0.anyValue }
            )
        }
        return events.sorted {
            if $0.relativeMs == $1.relativeMs {
                return $0.entry.timestamp < $1.entry.timestamp
            }
            return $0.relativeMs < $1.relativeMs
        }
    }

    static func reconstruct(at positionMs: Double, timeline: [ReplayTimelineEvent]) -> ReplayMomentState {
        var snapshot: [String: Any] = [:]
        var lastEvent: ReplayTimelineEvent?
        var nextEvent: ReplayTimelineEvent?

        for event in timeline {
            if event.relativeMs <= positionMs {
                apply(event: event, to: &snapshot)
                lastEvent = event
            } else {
                nextEvent = event
                break
            }
        }

        return ReplayMomentState(
            snapshot: snapshot,
            channels: extractChannels(from: snapshot),
            lastEvent: lastEvent,
            nextEvent: nextEvent
        )
    }

    private static func resolvedRelativeMs(for entry: EventLogEntry, startEpoch: Double) -> Double {
        if let value = entry.relativeMS {
            return max(0, value)
        }
        guard startEpoch > 0, let eventEpoch = parseISO(entry.timestamp) else {
            return 0
        }
        return max(0, (eventEpoch - startEpoch) * 1000.0)
    }

    private static func parseISO(_ value: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date.timeIntervalSince1970
        }
        return nil
    }

    private static func apply(event: ReplayTimelineEvent, to snapshot: inout [String: Any]) {
        let payload = event.payload

        if let state = payload["state"] as? [String: Any] {
            snapshot[event.entry.source] = state
        }

        if let mergedSnapshot = payload["snapshot"] as? [String: Any] {
            for (client, value) in mergedSnapshot {
                if let clientState = value as? [String: Any] {
                    snapshot[client] = clientState
                }
            }
        }
    }

    private static func extractChannels(from snapshot: [String: Any]) -> [ReplayChannelState] {
        let dirtyMixerState = (
            snapshot["dirtymixer_v1"] as? [String: Any]
                ?? snapshot.first(where: { $0.key.lowercased().contains("dirtymixer") })?.value as? [String: Any]
        )
        guard let dirtyMixerState,
              let rawChannels = dirtyMixerState["channels"] as? [Any]
        else {
            return []
        }

        var channelMap: [Int: ReplayChannelState] = [:]
        for raw in rawChannels {
            guard let channel = raw as? [String: Any] else { continue }
            let id = intValue(channel["id"]) ?? 0
            guard id > 0 else { continue }

            channelMap[id] = ReplayChannelState(
                id: id,
                inputA: boolValue(channel["input_a"]) ?? boolValue(channel["inputA"]) ?? false,
                inputB: boolValue(channel["input_b"]) ?? boolValue(channel["inputB"]) ?? false,
                mix: intValue(channel["mix"]) ?? 0
            )
        }

        if channelMap.isEmpty {
            return []
        }

        return (1 ... 9).map { id in
            channelMap[id] ?? ReplayChannelState(id: id, inputA: false, inputB: false, mix: 0)
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue.rounded())
        }
        if let boolValue = value as? Bool {
            return boolValue ? 1 : 0
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let intValue = value as? Int {
            return intValue != 0
        }
        if let doubleValue = value as? Double {
            return doubleValue != 0
        }
        if let stringValue = value as? String {
            return ["1", "true", "yes", "on"].contains(stringValue.lowercased())
        }
        return nil
    }
}

private struct ReplaySessionSheet: View {
    @ObservedObject var state: CatalogState
    let session: SessionRecord
    let eventLog: EventLogRecord
    let theme: CatalogTheme

    @Environment(\.dismiss) private var dismiss
    @State private var timeline: [ReplayTimelineEvent] = []
    @State private var positionMs: Double = 0
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var showingExportSheet = false
    @State private var exportName = ""

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let speedOptions: [Double] = [0.5, 1.0, 2.0, 4.0]

    private var totalDurationMs: Double {
        guard let last = timeline.last?.relativeMs, last.isFinite, last > 0 else {
            return 0
        }
        return last
    }

    private var moment: ReplayMomentState {
        ReplayEngine.reconstruct(at: positionMs, timeline: timeline)
    }

    private var progressPercent: Double {
        guard totalDurationMs > 0 else { return 0 }
        return min(1, max(0, positionMs / totalDurationMs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Replay")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.strongText)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 90)
            }

            Text("\(session.title) — \(session.date)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent)

            VStack(spacing: 6) {
                if totalDurationMs > 0 {
                    Slider(value: $positionMs, in: 0 ... totalDurationMs, step: 10)
                        .tint(theme.accent)
                } else {
                    Text("No timeline data")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(state.clockString(from: 0))
                    Spacer()
                    Text(state.clockString(from: positionMs))
                    Spacer()
                    Text(state.clockString(from: totalDurationMs))
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.muted)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(theme.panelInner)
                            .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: geo.size.width * progressPercent)
                    }
                }
                .frame(height: 10)
            }

            HStack(spacing: 8) {
                Button("◀◀") {
                    isPlaying = false
                    positionMs = 0
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 60)

                Button(isPlaying ? "⏸" : "▶") {
                    if timeline.isEmpty || totalDurationMs <= 0 { return }
                    isPlaying.toggle()
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 60)

                Button("-10s") {
                    positionMs = max(0, positionMs - 10_000)
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 70)

                Button("▶▶") {
                    guard totalDurationMs > 0 else { return }
                    positionMs = min(totalDurationMs, positionMs + 10_000)
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 60)

                Button("+10s") {
                    guard totalDurationMs > 0 else { return }
                    positionMs = min(totalDurationMs, positionMs + 10_000)
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 70)

                Button("Last Snap") {
                    guard let snap = lastSnapshotPositionMs else { return }
                    positionMs = snap
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 90)
                .disabled(lastSnapshotPositionMs == nil)

                Spacer()

                Text("Speed:")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)

                ForEach(speedOptions, id: \.self) { speed in
                    Button(speed == floor(speed) ? "\(Int(speed))x" : "\(speed)x") {
                        playbackSpeed = speed
                    }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 52)
                    .overlay(
                        Rectangle().stroke(playbackSpeed == speed ? theme.accent : .clear, lineWidth: 1)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current state at this moment:")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.strongText)

                if moment.channels.isEmpty {
                    Text("No DirtyMixer state available at this position")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.muted)
                } else {
                    ForEach(Array(stride(from: 0, to: moment.channels.count, by: 3)), id: \.self) { startIndex in
                        let endIndex = min(startIndex + 3, moment.channels.count)
                        let line = moment.channels[startIndex ..< endIndex]
                            .map { "CH\($0.id) A:\($0.inputA ? 1 : 0) B:\($0.inputB ? 1 : 0) M:\($0.mix)" }
                            .joined(separator: "   ")
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.text)
                    }
                }
            }
            .padding(8)
            .background(theme.panelInner)
            .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

            Text("Last event: \(moment.lastEvent?.entry.summary ?? "None yet")")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.strongText)

            if let last = moment.lastEvent {
                Text("Event type: [\(last.entry.type)] from \(last.entry.source)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
            }

            Text(nextEventDescription())
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.muted)

            VStack(alignment: .leading, spacing: 4) {
                Text("Event Stream")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.strongText)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(timeline.suffix(180)) { event in
                            Text("\(state.clockString(from: event.relativeMs))  [\(event.entry.type)]  \(event.entry.summary)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(eventColor(for: event.entry.type))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 120)
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button("Replay to Hardware") {
                    state.replaySnapshotToHardware(moment.snapshot, at: positionMs)
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .disabled(!state.nexusClient.isConnected || moment.snapshot.isEmpty)
                .help(state.nexusClient.isConnected
                    ? "Send reconstructed state at this moment to Nexus"
                    : "Connect to Nexus to replay to hardware")

                Button("Export This Moment") {
                    exportName = "Replay Export \(state.clockString(from: positionMs))"
                    showingExportSheet = true
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .disabled(moment.snapshot.isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 520)
        .background(theme.background)
        .onAppear {
            timeline = ReplayEngine.timeline(from: eventLog)
            if totalDurationMs <= 0 {
                positionMs = 0
                isPlaying = false
            } else if positionMs > totalDurationMs {
                positionMs = totalDurationMs
            }
        }
        .onReceive(timer) { _ in
            guard isPlaying else { return }
            guard totalDurationMs > 0 else {
                isPlaying = false
                positionMs = 0
                return
            }
            if positionMs >= totalDurationMs {
                isPlaying = false
                return
            }
            positionMs = min(totalDurationMs, positionMs + (50.0 * playbackSpeed))
            if positionMs >= totalDurationMs {
                isPlaying = false
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ReplayExportSheet(
                defaultName: exportName,
                onSave: { name in
                    state.exportReplayMoment(
                        snapshot: moment.snapshot,
                        name: name,
                        positionMs: positionMs,
                        notes: replayExportNotes()
                    )
                }
            )
        }
    }

    private var lastSnapshotPositionMs: Double? {
        timeline.reversed().first(where: { isSnapshotEvent($0) })?.relativeMs
    }

    private func nextEventDescription() -> String {
        guard let next = moment.nextEvent else {
            return "Next event: End of session"
        }
        let delta = max(0, next.relativeMs - positionMs)
        return "Next event: \(next.entry.summary) (in \(state.clockString(from: delta)))"
    }

    private func eventColor(for type: String) -> Color {
        if type.contains("error") {
            return .red
        }
        if type.contains("scene_save") {
            return .orange
        }
        if type.contains("scene_recall") {
            return .pink
        }
        if type.contains("recording") {
            return .yellow
        }
        if type.contains("state_update") {
            return theme.accent
        }
        return theme.text
    }

    private func isSnapshotEvent(_ event: ReplayTimelineEvent) -> Bool {
        event.entry.type.contains("scene_save")
            || event.entry.summary.lowercased().contains("snapshot")
    }

    private func replayExportNotes() -> String {
        let last = moment.lastEvent?.entry.summary ?? "None"
        let next = moment.nextEvent?.entry.summary ?? "End of session"
        return [
            "Replay Export",
            "Session: \(session.title)",
            "Position: \(state.clockString(from: positionMs)) / \(state.clockString(from: totalDurationMs))",
            "Last event: \(last)",
            "Next event: \(next)",
            "Exported at: \(state.prettyTimestamp(ISO8601DateFormatter().string(from: Date())))",
        ].joined(separator: "\n")
    }
}

private struct ReplayExportSheet: View {
    let defaultName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(defaultName: String, onSave: @escaping (String) -> Void) {
        self.defaultName = defaultName
        self.onSave = onSave
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Replay Moment")
                .font(.headline)
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private struct PresetNameSheet: View {
    let defaultName: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(defaultName: String, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.defaultName = defaultName
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Snapshot As Preset")
                .font(.headline)

            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                Button("Save") {
                    onConfirm(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
