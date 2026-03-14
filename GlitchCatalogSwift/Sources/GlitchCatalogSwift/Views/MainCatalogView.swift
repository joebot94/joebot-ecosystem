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

    var label: String {
        switch self {
        case .dos:
            return "DOS"
        case .neon:
            return "Neon"
        case .amber:
            return "Amber"
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
                    .frame(width: 316)

                mainGrid
            }
            .padding(8)
        }
        .background(theme.background)
        .foregroundStyle(theme.text)
        .toolbar {
            ToolbarItemGroup {
                Button("Snapshot") {
                    state.sendSnapshot()
                }
                .buttonStyle(RetroButtonStyle(theme: theme))
                .frame(width: 120)
                .disabled(!state.nexusClient.isConnected)

                Picker("Theme", selection: $preset) {
                    ForEach(CatalogThemePreset.allCases) { item in
                        Text(item.windowTitle).tag(item)
                    }
                }
                .frame(width: 170)

                NexusStatusIndicator(client: state.nexusClient)
            }
        }
        .onChange(of: kindOptions) { _, next in
            if !next.contains(selectedKindFilter) {
                selectedKindFilter = "All kinds"
            }
        }
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
                                state.selectedSessionID = session.id
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
                    Button("New Session") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Edit Session") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                    Button("Delete Session") {}
                        .buttonStyle(RetroButtonStyle(theme: theme))
                }
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

                Text("Tapes: \(state.tapesForSelectedSession.count) | Gear: \(state.gearChainForSelectedSession.count) | Media: \(filteredMedia.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)

                Button("Export Media CSV") {}
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .frame(width: 360)
            }

            RetroPanel(title: "Preview", theme: theme) {
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
