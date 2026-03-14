import Combine
import Foundation
import JoebotSDK

struct PendingSnapshotDraft: Identifiable {
    let id: String
    let createdAtISO: String
    let defaultName: String
    let snapshot: [String: Any]
}

@MainActor
final class CatalogState: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var tapes: [TapeRecord] = []
    @Published var gear: [GearRecord] = []
    @Published var sessionGear: [SessionGearRecord] = []
    @Published var media: [MediaRecord] = []
    @Published var presets: [PresetRecord] = []

    @Published var selectedSessionID: UUID?
    @Published var selectedPresetID: String?

    @Published var pendingSnapshotDraft: PendingSnapshotDraft?
    @Published var isSnapshotInFlight = false
    @Published var toastMessage: String?

    let nexusClient = NexusClient(clientId: "glitch_catalog", clientType: "catalog")

    private let store = JBTStore()
    private var subscriptions: Set<AnyCancellable> = []
    private var documentsBySessionID: [UUID: SessionDocument] = [:]

    init() {
        loadSessionDocuments()

        nexusClient.capabilitiesProvider = {
            [
                "scene_save": true,
                "scene_recall": true,
                "jbt_storage": true,
                "snapshot": true,
            ]
        }

        nexusClient.currentStateProvider = { [weak self] in
            self?.statePayload() ?? [:]
        }

        nexusClient.onMessage = { [weak self] message in
            self?.handleNexusMessage(message)
        }

        // Forward NexusClient updates so UI banners and controls stay current.
        nexusClient.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return documentsBySessionID[selectedSessionID]?.session
    }

    var selectedPreset: PresetRecord? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    var tapesForSelectedSession: [TapeRecord] {
        tapes
    }

    var mediaForSelectedSession: [MediaRecord] {
        media
    }

    var gearChainForSelectedSession: [String] {
        let linkedGearIDs = sessionGear.map(\.gearID)
        return linkedGearIDs.compactMap { gearID in
            gear.first(where: { $0.id == gearID })?.name
        }
    }

    func selectSession(_ sessionID: UUID?) {
        selectedSessionID = sessionID

        guard let sessionID, let document = documentsBySessionID[sessionID] else {
            tapes = []
            gear = []
            sessionGear = []
            media = []
            presets = []
            selectedPresetID = nil
            return
        }

        tapes = document.tapes
        gear = document.gear
        sessionGear = document.sessionGear
        media = document.media
        presets = document.presets.sorted { $0.createdAt > $1.createdAt }
        if let selectedPresetID, presets.contains(where: { $0.id == selectedPresetID }) {
            self.selectedPresetID = selectedPresetID
        } else {
            self.selectedPresetID = nil
        }
    }

    func selectPreset(_ presetID: String?) {
        selectedPresetID = presetID
    }

    func createSession(title: String, date: String, location: String, notes: String) {
        let session = SessionRecord(
            id: UUID(),
            title: title,
            date: date,
            location: location,
            notes: notes
        )

        let document = SessionDocument(
            name: title,
            session: session,
            tapes: [],
            gear: [],
            sessionGear: [],
            media: [],
            presets: []
        )

        documentsBySessionID[session.id] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: session.id)
    }

    func updateSelectedSession(title: String, date: String, location: String, notes: String) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else { return }

        document.session.title = title
        document.session.date = date
        document.session.location = location
        document.session.notes = notes
        document.name = title

        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: selectedSessionID)
    }

    func deleteSelectedSession() {
        guard let selectedSessionID else { return }
        documentsBySessionID[selectedSessionID] = nil
        store.deleteSessionDocument(sessionID: selectedSessionID)

        let nextSelection = sessions
            .filter { $0.id != selectedSessionID }
            .sorted { $0.date > $1.date }
            .first?
            .id

        refreshSessionIndex(selecting: nextSelection)
    }

    func sendSnapshot() {
        guard nexusClient.isConnected else {
            showToast("Connect to Nexus to snapshot")
            return
        }
        guard selectedSession != nil else {
            showToast("Select a session first")
            return
        }

        isSnapshotInFlight = true
        nexusClient.sendMessage(type: "scene_save", payload: [
            "session_name": selectedSession?.title ?? "",
        ])
    }

    func cancelPendingSnapshot() {
        pendingSnapshotDraft = nil
        isSnapshotInFlight = false
    }

    func confirmPendingSnapshot(name: String) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else {
            cancelPendingSnapshot()
            return
        }
        guard let draft = pendingSnapshotDraft else { return }

        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draft.defaultName : name
        let preset = PresetRecord(
            id: draft.id,
            name: finalName,
            createdAt: draft.createdAtISO,
            snapshot: AnyCodable.wrapDictionary(draft.snapshot)
        )

        document.presets.insert(preset, at: 0)
        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)

        pendingSnapshotDraft = nil
        isSnapshotInFlight = false
        refreshSessionIndex(selecting: selectedSessionID)
        selectedPresetID = preset.id
        showToast("Preset saved")
    }

    func deletePreset(_ presetID: String) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else { return }

        document.presets.removeAll { $0.id == presetID }
        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)

        refreshSessionIndex(selecting: selectedSessionID)
        if selectedPresetID == presetID {
            selectedPresetID = nil
        }
        showToast("Preset deleted")
    }

    func recallPreset(_ preset: PresetRecord) {
        guard nexusClient.isConnected else {
            showToast("Connect to Nexus to recall")
            return
        }

        let snapshot = preset.snapshot.mapValues { $0.anyValue }
        nexusClient.sendMessage(type: "scene_recall", payload: [
            "preset_id": preset.id,
            "preset_name": preset.name,
            "snapshot": snapshot,
        ])
    }

    func presetDetailsText(_ preset: PresetRecord) -> String {
        let payload = preset.snapshot.mapValues { $0.anyValue }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "Unable to render preset snapshot"
        }
        return text
    }

    func prettyTimestamp(_ value: String) -> String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: value) else { return value }

        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: date)
    }

    static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parse(dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }

    private func loadSessionDocuments() {
        let docs = store.loadSessionDocuments()
        documentsBySessionID = Dictionary(uniqueKeysWithValues: docs.map { ($0.session.id, $0) })
        refreshSessionIndex(selecting: docs.first?.session.id)
    }

    private func refreshSessionIndex(selecting preferredID: UUID?) {
        sessions = documentsBySessionID.values
            .map(\.session)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.date > rhs.date
            }

        let targetID = preferredID ?? sessions.first?.id
        selectSession(targetID)
    }

    private func handleNexusMessage(_ message: NexusMessage) {
        switch message.type {
        case "scene_saved":
            handleSceneSaved(message)
        case "scene_recalled":
            showToast("Preset recalled successfully")
        default:
            break
        }
    }

    private func handleSceneSaved(_ message: NexusMessage) {
        isSnapshotInFlight = false

        guard let snapshot = message.payload["snapshot"]?.anyValue as? [String: Any] else {
            showToast("Snapshot failed")
            return
        }

        let now = Date()
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let defaultName = "Snapshot \(stampFormatter.string(from: now))"
        let iso = ISO8601DateFormatter().string(from: now)

        let shortID = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)

        pendingSnapshotDraft = PendingSnapshotDraft(
            id: "preset_\(shortID)",
            createdAtISO: iso,
            defaultName: defaultName,
            snapshot: snapshot
        )
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self, self.toastMessage == message else { return }
                self.toastMessage = nil
            }
        }
    }

    private func statePayload() -> [String: Any] {
        [
            "selected_session": selectedSession?.title ?? "none",
            "session_count": sessions.count,
            "tape_count": tapesForSelectedSession.count,
            "media_count": mediaForSelectedSession.count,
            "gear_chain": gearChainForSelectedSession,
            "preset_count": presets.count,
        ]
    }
}
