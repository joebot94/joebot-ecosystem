import Combine
import Foundation
import JoebotSDK
import AppKit
import AVFoundation
import CryptoKit
import CoreMedia
import ImageIO

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

    func createSession(title: String, date: String, location: String, notes: String, tags: [String]) {
        let session = SessionRecord(
            id: UUID(),
            title: title,
            date: date,
            location: location,
            notes: notes,
            tags: tags
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

    func updateSelectedSession(title: String, date: String, location: String, notes: String, tags: [String]) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else { return }

        document.session.title = title
        document.session.date = date
        document.session.location = location
        document.session.notes = notes
        document.session.tags = tags
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

    func attachPhotosToSelectedGear(urls: [URL]) {
        guard let selectedGearLinkID else {
            showToast("Select a gear item first")
            return
        }
        guard !urls.isEmpty else { return }

        var addedCount = 0
        updateSelectedDocument { document in
            guard let linkIndex = document.sessionGear.firstIndex(where: { $0.id == selectedGearLinkID }) else { return }
            var existing = Set(document.sessionGear[linkIndex].photos)
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let path = url.path
                if !existing.contains(path) {
                    existing.insert(path)
                    document.sessionGear[linkIndex].photos.append(path)
                    addedCount += 1
                }
            }
        }

        showToast("Added \(addedCount) gear photo(s)")
    }

    func openSelectedGearPhoto() {
        guard let firstPath = selectedGearRow?.link.photos.first else {
            showToast("No gear photo attached")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: firstPath))
    }

    func addMediaFiles(urls: [URL]) {
        guard let selectedSessionID else {
            showToast("Select a session first")
            return
        }
        guard !urls.isEmpty else { return }

        var newestMediaID: UUID?
        var importedCount = 0
        updateSelectedDocument { document in
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try? url.resourceValues(
                    forKeys: [.creationDateKey, .fileSizeKey, .nameKey, .isDirectoryKey]
                )
                if values?.isDirectory == true {
                    continue
                }

                let fileName = values?.name ?? url.lastPathComponent
                let createdAt = values?.creationDate ?? Date()
                let fileSize = values?.fileSize ?? 0
                let kind = inferMediaKind(from: url.pathExtension)
                let metadata = mediaMetadata(for: url, kind: kind)
                let checksum = sha256(for: url) ?? ""
                let noteSuffix = "size=\(fileSize) bytes"

                let record = MediaRecord(
                    id: UUID(),
                    sessionID: selectedSessionID,
                    filePath: url.path,
                    kind: kind,
                    checksum: checksum,
                    duration: metadata.duration,
                    width: metadata.width,
                    height: metadata.height,
                    codec: metadata.codec,
                    createdAt: ISO8601DateFormatter().string(from: createdAt),
                    notes: "\(fileName) | \(noteSuffix)",
                    thumbnailPath: "",
                    toolPath: "",
                    settingsNotes: ""
                )
                newestMediaID = record.id
                document.media.append(record)
                importedCount += 1
            }
        }

        if let newestMediaID {
            selectedMediaID = newestMediaID
            showToast("Added \(importedCount) media file(s)")
        }
    }

    func updateSelectedMedia(kind: String, notes: String, toolPath: String, settingsNotes: String) {
        guard let selectedMediaID else { return }

        updateSelectedDocument { document in
            guard let index = document.media.firstIndex(where: { $0.id == selectedMediaID }) else { return }
            document.media[index].kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            document.media[index].notes = notes
            document.media[index].toolPath = toolPath.trimmingCharacters(in: .whitespacesAndNewlines)
            document.media[index].settingsNotes = settingsNotes
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

    func exportSelectedSessionJSON() {
        guard let selectedSessionID, let document = documentsBySessionID[selectedSessionID] else {
            showToast("Select a session first")
            return
        }

        let exportURL = exportsDirectoryURL()
            .appendingPathComponent("session_\(selectedSessionID.uuidString.lowercased())_\(exportTimestampTag()).json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: exportURL, options: [.atomic])
            showToast("Session export saved: \(exportURL.lastPathComponent)")
        } catch {
            showToast("Session export failed")
        }
    }

    func exportSelectedMediaCSV(mediaItems: [MediaRecord]) {
        guard let selectedSession else {
            showToast("Select a session first")
            return
        }

        let rows = mediaItems
        let exportURL = exportsDirectoryURL()
            .appendingPathComponent("media_\(selectedSession.id.uuidString.lowercased())_\(exportTimestampTag()).csv")

        var csv = "id,session_id,file_path,kind,checksum,duration,width,height,codec,created_at,notes,thumbnail_path,tool_path,settings_notes\n"
        for row in rows {
            csv.append(
                [
                    row.id.uuidString,
                    row.sessionID.uuidString,
                    csvEscape(row.filePath),
                    csvEscape(row.kind),
                    csvEscape(row.checksum),
                    String(format: "%.3f", row.duration),
                    String(row.width),
                    String(row.height),
                    csvEscape(row.codec),
                    csvEscape(row.createdAt),
                    csvEscape(row.notes),
                    csvEscape(row.thumbnailPath),
                    csvEscape(row.toolPath),
                    csvEscape(row.settingsNotes),
                ].joined(separator: ",")
            )
            csv.append("\n")
        }

        do {
            try csv.write(to: exportURL, atomically: true, encoding: .utf8)
            showToast("Media CSV saved: \(exportURL.lastPathComponent)")
        } catch {
            showToast("Media CSV export failed")
        }
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

    func replaySnapshotToHardware(_ snapshot: [String: Any], at positionMs: Double) {
        guard nexusClient.isConnected else {
            showToast("Connect to Nexus to replay to hardware")
            return
        }
        guard !snapshot.isEmpty else {
            showToast("No state available at this moment")
            return
        }

        nexusClient.sendMessage(type: "scene_recall", payload: [
            "snapshot": snapshot,
        ])
        showToast("State restored to \(clockString(from: positionMs))")
    }

    func exportReplayMoment(snapshot: [String: Any], name: String, positionMs: Double) {
        guard !snapshot.isEmpty else {
            showToast("No state available at this moment")
            return
        }
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else {
            return
        }

        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "Replay Export \(clockString(from: positionMs))"

        let shortID = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
        let preset = PresetRecord(
            id: "preset_\(shortID)",
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            createdAt: iso,
            snapshot: AnyCodable.wrapDictionary(snapshot)
        )

        document.presets.insert(preset, at: 0)
        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: selectedSessionID)
        selectedPresetID = preset.id
        showToast("Replay moment exported")
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

    func clockString(from positionMs: Double) -> String {
        let totalSeconds = max(0, Int(positionMs / 1000.0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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

    private func mediaMetadata(for url: URL, kind: String) -> (duration: Double, width: Int, height: Int, codec: String) {
        switch kind {
        case "video":
            let asset = AVAsset(url: url)
            let duration = max(0, CMTimeGetSeconds(asset.duration).isFinite ? CMTimeGetSeconds(asset.duration) : 0)
            let track = asset.tracks(withMediaType: .video).first
            var width = 0
            var height = 0
            var codec = ""

            if let track {
                let transformed = track.naturalSize.applying(track.preferredTransform)
                width = Int(abs(transformed.width).rounded())
                height = Int(abs(transformed.height).rounded())
                if let firstDescription = track.formatDescriptions.first {
                    let desc = firstDescription as! CMFormatDescription
                    codec = fourCC(from: CMFormatDescriptionGetMediaSubType(desc))
                }
            }
            return (duration, width, height, codec)

        case "image":
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else {
                return (0, 0, 0, "")
            }
            let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            return (0, width, height, url.pathExtension.uppercased())

        default:
            return (0, 0, 0, "")
        }
    }

    private func sha256(for url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            hasher.update(data: Data(buffer[0 ..< read]))
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
    }

    private func fourCC(from code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let text = String(bytes: bytes, encoding: .ascii) ?? "\(code)"
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exportsDirectoryURL() -> URL {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = docsDir
            .appendingPathComponent("Joebot", isDirectory: true)
            .appendingPathComponent("GlitchCatalog", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func exportTimestampTag() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
