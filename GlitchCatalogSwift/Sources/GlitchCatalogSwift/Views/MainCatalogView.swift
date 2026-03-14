import JoebotSDK
import SwiftUI

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

                Text("Tapes: \(state.tapesForSelectedSession.count) | Gear: \(state.gearChainForSelectedSession.count) | Media: \(filteredMedia.count) | Presets: \(state.presets.count)")
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

                        Spacer(minLength: 0)
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
                            Text("\(tape.tapeID) [\(tape.format)]  \(tape.label)")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("Add Tape") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Edit Selected") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Delete Selected") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                }
            }
        }
    }

    private var gearPanel: some View {
        RetroPanel(title: "Gear Chain (Session)", theme: theme) {
            VStack(spacing: 6) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.gearChainForSelectedSession.enumerated()), id: \.offset) { idx, item in
                            Text("\(idx + 1). \(item)")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("Add Gear...") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Edit Gear...") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Remove From Session") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
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
                            Text("\(item.kind): \(item.filePath)")
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(2)
                }
                .background(theme.panelInner)
                .overlay(Rectangle().stroke(theme.border, lineWidth: 1))

                HStack(spacing: 6) {
                    Button("Add Media Files...") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Edit Metadata...") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Open Selected") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Delete Selected") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
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
