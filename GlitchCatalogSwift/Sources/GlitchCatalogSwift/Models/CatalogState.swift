import Combine
import Foundation
import JoebotSDK
import AppKit

struct PendingSnapshotDraft: Identifiable {
    let id: String
    let createdAtISO: String
    let defaultName: String
    let snapshot: [String: Any]
}

struct GearChainRow: Identifiable, Hashable {
    var id: UUID { link.id }
    let link: SessionGearRecord
    let gear: GearRecord
}

@MainActor
final class CatalogState: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var tapes: [TapeRecord] = []
    @Published var gear: [GearRecord] = []
    @Published var sessionGear: [SessionGearRecord] = []
    @Published var media: [MediaRecord] = []
    @Published var presets: [PresetRecord] = []
    @Published var eventLog: EventLogRecord?

    @Published var selectedSessionID: UUID?
    @Published var selectedPresetID: String?
    @Published var selectedTapeID: String?
    @Published var selectedGearLinkID: UUID?
    @Published var selectedMediaID: UUID?

    @Published var pendingSnapshotDraft: PendingSnapshotDraft?
    @Published var isSnapshotInFlight = false
    @Published var recordingSessionID: String?
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
                "recording": true,
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

    var selectedSessionExternalID: String? {
        selectedSessionID?.uuidString.lowercased()
    }

    var isRecordingCurrentSession: Bool {
        guard let selectedSessionExternalID else { return false }
        return recordingSessionID == selectedSessionExternalID
    }

    var selectedPreset: PresetRecord? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    var selectedTape: TapeRecord? {
        guard let selectedTapeID else { return nil }
        return tapes.first(where: { $0.id == selectedTapeID })
    }

    var selectedGearRow: GearChainRow? {
        guard let selectedGearLinkID else { return nil }
        return gearRowsForSelectedSession.first(where: { $0.id == selectedGearLinkID })
    }

    var selectedMedia: MediaRecord? {
        guard let selectedMediaID else { return nil }
        return media.first(where: { $0.id == selectedMediaID })
    }

    var tapesForSelectedSession: [TapeRecord] {
        tapes
    }

    var mediaForSelectedSession: [MediaRecord] {
        media
    }

    var gearChainForSelectedSession: [String] {
        gearRowsForSelectedSession.map(\.gear.name)
    }

    var gearRowsForSelectedSession: [GearChainRow] {
        sessionGear.compactMap { link in
            guard let linked = gear.first(where: { $0.id == link.gearID }) else { return nil }
            return GearChainRow(link: link, gear: linked)
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
            eventLog = nil
            selectedPresetID = nil
            selectedTapeID = nil
            selectedGearLinkID = nil
            selectedMediaID = nil
            return
        }

        tapes = document.tapes
        gear = document.gear
        sessionGear = document.sessionGear
        media = document.media
        presets = document.presets.sorted { $0.createdAt > $1.createdAt }
        eventLog = document.eventLog

        if let selectedPresetID, presets.contains(where: { $0.id == selectedPresetID }) {
            self.selectedPresetID = selectedPresetID
        } else {
            self.selectedPresetID = nil
        }
        if let selectedTapeID, tapes.contains(where: { $0.id == selectedTapeID }) {
            self.selectedTapeID = selectedTapeID
        } else {
            self.selectedTapeID = nil
        }
        if let selectedGearLinkID, sessionGear.contains(where: { $0.id == selectedGearLinkID }) {
            self.selectedGearLinkID = selectedGearLinkID
        } else {
            self.selectedGearLinkID = nil
        }
        if let selectedMediaID, media.contains(where: { $0.id == selectedMediaID }) {
            self.selectedMediaID = selectedMediaID
        } else {
            self.selectedMediaID = nil
        }
    }

    func selectPreset(_ presetID: String?) {
        selectedPresetID = presetID
    }

    func selectTape(_ tapeID: String?) {
        selectedTapeID = tapeID
    }

    func selectGearLink(_ gearLinkID: UUID?) {
        selectedGearLinkID = gearLinkID
    }

    func selectMedia(_ mediaID: UUID?) {
        selectedMediaID = mediaID
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
            presets: [],
            eventLog: nil
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

    func addTape(tapeID: String, format: String, label: String, storageLocation: String, notes: String) {
        guard let selectedSessionID else {
            showToast("Select a session first")
            return
        }

        let normalizedTapeID = tapeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "T-\(String(format: "%03d", tapes.count + 1))"
            : tapeID.trimmingCharacters(in: .whitespacesAndNewlines)

        updateSelectedDocument { document in
            document.tapes.append(
                TapeRecord(
                    sessionID: selectedSessionID,
                    tapeID: normalizedTapeID,
                    format: format.trimmingCharacters(in: .whitespacesAndNewlines),
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    storageLocation: storageLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes
                )
            )
        }

        selectedTapeID = normalizedTapeID
        showToast("Tape added")
    }

    func updateSelectedTape(tapeID: String, format: String, label: String, storageLocation: String, notes: String) {
        guard let selectedTapeID else { return }
        let normalizedTapeID = tapeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedTapeID : tapeID

        updateSelectedDocument { document in
            guard let index = document.tapes.firstIndex(where: { $0.id == selectedTapeID }) else { return }
            document.tapes[index].tapeID = normalizedTapeID
            document.tapes[index].format = format.trimmingCharacters(in: .whitespacesAndNewlines)
            document.tapes[index].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            document.tapes[index].storageLocation = storageLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            document.tapes[index].notes = notes
        }

        self.selectedTapeID = normalizedTapeID
        showToast("Tape updated")
    }

    func deleteSelectedTape() {
        guard let selectedTapeID else { return }

        updateSelectedDocument { document in
            document.tapes.removeAll { $0.id == selectedTapeID }
        }

        self.selectedTapeID = nil
        showToast("Tape deleted")
    }

    func addGearToSession(name: String, notes: String) {
        guard let selectedSessionID else {
            showToast("Select a session first")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let gearRecord = GearRecord(id: UUID(), name: trimmedName)
        let link = SessionGearRecord(
            id: UUID(),
            sessionID: selectedSessionID,
            gearID: gearRecord.id,
            notes: notes
        )

        updateSelectedDocument { document in
            document.gear.append(gearRecord)
            document.sessionGear.append(link)
        }

        selectedGearLinkID = link.id
        showToast("Gear added")
    }

    func updateSelectedGear(name: String, notes: String) {
        guard let selectedGearLinkID else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        updateSelectedDocument { document in
            guard let linkIndex = document.sessionGear.firstIndex(where: { $0.id == selectedGearLinkID }) else { return }
            let gearID = document.sessionGear[linkIndex].gearID
            if let gearIndex = document.gear.firstIndex(where: { $0.id == gearID }) {
                document.gear[gearIndex].name = trimmedName
            }
            document.sessionGear[linkIndex].notes = notes
        }

        showToast("Gear updated")
    }

    func removeSelectedGearFromSession() {
        guard let selectedGearLinkID else { return }

        updateSelectedDocument { document in
            document.sessionGear.removeAll { $0.id == selectedGearLinkID }
            let remainingGearIDs = Set(document.sessionGear.map(\.gearID))
            document.gear.removeAll { !remainingGearIDs.contains($0.id) }
        }

        self.selectedGearLinkID = nil
        showToast("Gear removed")
    }

    func addMediaFiles(urls: [URL]) {
        guard let selectedSessionID else {
            showToast("Select a session first")
            return
        }
        guard !urls.isEmpty else { return }

        var newestMediaID: UUID?
        updateSelectedDocument { document in
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .nameKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    continue
                }

                let fileName = values?.name ?? url.lastPathComponent
                let createdAt = values?.creationDate ?? Date()
                let fileSize = values?.fileSize
                let kind = inferMediaKind(from: url.pathExtension)
                let noteSuffix = fileSize.map { "size=\($0) bytes" } ?? "size=unknown"

                let record = MediaRecord(
                    id: UUID(),
                    sessionID: selectedSessionID,
                    filePath: url.path,
                    kind: kind,
                    checksum: "",
                    duration: 0,
                    width: 0,
                    height: 0,
                    codec: "",
                    createdAt: ISO8601DateFormatter().string(from: createdAt),
                    notes: "\(fileName) | \(noteSuffix)",
                    thumbnailPath: ""
                )
                newestMediaID = record.id
                document.media.append(record)
            }
        }

        if let newestMediaID {
            selectedMediaID = newestMediaID
            showToast("Added \(urls.count) media file(s)")
        }
    }

    func updateSelectedMedia(kind: String, notes: String) {
        guard let selectedMediaID else { return }

        updateSelectedDocument { document in
            guard let index = document.media.firstIndex(where: { $0.id == selectedMediaID }) else { return }
            document.media[index].kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            document.media[index].notes = notes
        }

        showToast("Media updated")
    }

    func deleteSelectedMedia() {
        guard let selectedMediaID else { return }

        updateSelectedDocument { document in
            document.media.removeAll { $0.id == selectedMediaID }
        }

        self.selectedMediaID = nil
        showToast("Media removed")
    }

    func openSelectedMedia() {
        guard let selectedMedia else { return }
        let fileURL = URL(fileURLWithPath: selectedMedia.filePath)
        NSWorkspace.shared.open(fileURL)
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

    func toggleRecording() {
        guard nexusClient.isConnected else {
            showToast("Connect to Nexus to record")
            return
        }
        guard let selectedSession = selectedSession, let selectedSessionExternalID else {
            showToast("Select a session first")
            return
        }

        if isRecordingCurrentSession {
            nexusClient.sendMessage(type: "recording.stop", payload: [
                "session_id": selectedSessionExternalID,
            ])
        } else {
            nexusClient.sendMessage(type: "recording.start", payload: [
                "session_name": selectedSession.title,
                "session_id": selectedSessionExternalID,
            ])
        }
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

    func eventTimelineRows() -> [String] {
        guard let eventLog else { return [] }
        return eventLog.events.map { entry in
            let ts = prettyTimestamp(entry.timestamp)
            return "\(ts)  [\(entry.type)]  \(entry.summary)"
        }
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
        out.dateFormat = "yyyy-MM-dd HH:mm:ss"
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
        case "recording.started":
            handleRecordingStarted(message)
        case "recording.stopped":
            handleRecordingStopped(message)
        case "recording.log":
            handleRecordingLog(message)
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

    private func handleRecordingStarted(_ message: NexusMessage) {
        guard let sessionID = message.payload["session_id"]?.anyValue as? String else {
            return
        }
        recordingSessionID = sessionID
        showToast("Recording started")
    }

    private func handleRecordingStopped(_ message: NexusMessage) {
        guard let sessionID = message.payload["session_id"]?.anyValue as? String else {
            return
        }
        if recordingSessionID == sessionID {
            recordingSessionID = nil
        }
        showToast("Recording stopped")
        nexusClient.sendMessage(type: "recording.request", payload: [
            "session_id": sessionID,
        ])
    }

    private func handleRecordingLog(_ message: NexusMessage) {
        let found = (message.payload["found"]?.anyValue as? Bool) ?? false
        guard found else {
            showToast("No event log found")
            return
        }

        guard let rawLog = message.payload["log"]?.anyValue,
              let parsed = decodeEventLog(from: rawLog)
        else {
            showToast("Failed to decode event log")
            return
        }

        persistEventLog(parsed)
        showToast("Event log synced")
    }

    private func decodeEventLog(from value: Any) -> EventLogRecord? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode(EventLogRecord.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    private func persistEventLog(_ log: EventLogRecord) {
        let sessionUUID: UUID? = UUID(uuidString: log.sessionID)
        let targetID = sessionUUID ?? selectedSessionID
        guard let targetID, var document = documentsBySessionID[targetID] else {
            return
        }

        document.eventLog = log
        documentsBySessionID[targetID] = document
        store.saveSessionDocument(document)

        if selectedSessionID == targetID {
            eventLog = log
        }
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
            "is_recording": isRecordingCurrentSession,
        ]
    }

    private func updateSelectedDocument(_ mutate: (inout SessionDocument) -> Void) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else { return }
        mutate(&document)
        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: selectedSessionID)
    }

    private func inferMediaKind(from extensionValue: String) -> String {
        let ext = extensionValue.lowercased()
        if ["mov", "mp4", "m4v", "avi", "mkv", "webm"].contains(ext) {
            return "video"
        }
        if ["jpg", "jpeg", "png", "bmp", "gif", "tiff", "webp", "heic"].contains(ext) {
            return "image"
        }
        if ["py", "js", "sh", "swift", "txt", "md", "json"].contains(ext) {
            return "script"
        }
        return "reference"
    }
}
