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
    @State private var showingNewSessionSheet = false
    @State private var showingEditSessionSheet = false
    @State private var showingDeleteSessionAlert = false
    @State private var showingAddTapeSheet = false
    @State private var showingEditTapeSheet = false
    @State private var showingAddGearSheet = false
    @State private var showingEditGearSheet = false
    @State private var showingMediaImporter = false
    @State private var showingEditMediaSheet = false

    private var theme: CatalogTheme { preset.theme }

    private var filteredSessions: [SessionRecord] {
        guard !searchText.isEmpty else { return state.sessions }
        let query = searchText.lowercased()
        return state.sessions.filter { session in
            session.title.lowercased().contains(query)
                || session.location.lowercased().contains(query)
                || session.date.lowercased().contains(query)
                || session.notes.lowercased().contains(query)
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
                onSave: { title, date, location, notes in
                    state.createSession(
                        title: title,
                        date: CatalogState.format(date: date),
                        location: location,
                        notes: notes
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
                    onSave: { title, date, location, notes in
                        state.updateSelectedSession(
                            title: title,
                            date: CatalogState.format(date: date),
                            location: location,
                            notes: notes
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
                    onSave: { kind, notes in
                        state.updateSelectedMedia(kind: kind, notes: notes)
                    }
                )
            } else {
                Text("No media selected")
                    .frame(width: 420, height: 220)
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
                                    Text("\(session.date) - \(session.title) [tags: ]")
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

                presetsSection
                    .frame(height: 240)
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

    private var mainGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tapesPanel
                gearPanel
                mediaPanel
            }

            HStack(spacing: 8) {
                Button("Export Session to JSON") {}
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 360)

                Text("Tapes: \(state.tapesForSelectedSession.count) | Gear: \(state.gearChainForSelectedSession.count) | Media: \(filteredMedia.count) | Presets: \(state.presets.count) | Events: \(state.eventLog?.events.count ?? 0)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)

                Button("Export Media CSV") {}
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 360)
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

                    Spacer()
                }

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
                    Button("Grid View") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                }
            }
        }
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
    let onSave: (String, Date, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var location: String
    @State private var notes: String

    init(
        mode: SessionEditorMode,
        initialTitle: String,
        initialDate: Date,
        initialLocation: String,
        initialNotes: String,
        onSave: @escaping (String, Date, String, String) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
        _location = State(initialValue: initialLocation)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.title)
                .font(.headline)

            TextField("Title", text: $title)
            DatePicker("Date", selection: $date, displayedComponents: [.date])
            TextField("Location", text: $location)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(4 ... 8)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(mode.actionLabel) {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), date, location, notes)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 280)
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
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var notes: String

    init(
        initialKind: String,
        initialNotes: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.onSave = onSave
        _kind = State(initialValue: initialKind)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Media Metadata")
                .font(.headline)

            TextField("Kind (video/image/script/reference)", text: $kind)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(kind.trimmingCharacters(in: .whitespacesAndNewlines), notes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 260)
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
