import Foundation

final class JBTStore {
    private let sessionsDirectoryURL: URL
    private let legacyFileURL: URL

    init() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        sessionsDirectoryURL = docsDir
            .appendingPathComponent("Joebot", isDirectory: true)
            .appendingPathComponent("GlitchCatalog", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        legacyFileURL = docsDir.appendingPathComponent("catalog_data.jbt")

        do {
            try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            print("[JBTStore] directory create error: \(error)")
        }
    }

    func loadSessionDocuments() -> [SessionDocument] {
        let fm = FileManager.default

        do {
            let files = try fm.contentsOfDirectory(
                at: sessionsDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension.lowercased() == "jbt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var docs: [SessionDocument] = []
            for url in files {
                do {
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder().decode(SessionDocument.self, from: data)
                    docs.append(decoded)
                } catch {
                    print("[JBTStore] failed to decode \(url.lastPathComponent): \(error)")
                }
            }

            if !docs.isEmpty {
                return docs
            }
        } catch {
            print("[JBTStore] directory read error: \(error)")
        }

        if let migrated = migrateLegacyIfPresent() {
            return migrated
        }

        let seeded = seedDocument()
        saveSessionDocument(seeded)
        return [seeded]
    }

    func saveSessionDocument(_ document: SessionDocument) {
        do {
            let encoded = try JSONEncoder().encode(document)
            try encoded.write(to: url(for: document.session.id), options: [.atomic])
        } catch {
            print("[JBTStore] save error: \(error)")
        }
    }

    func deleteSessionDocument(sessionID: UUID) {
        let targetURL = url(for: sessionID)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: targetURL)
        } catch {
            print("[JBTStore] delete error: \(error)")
        }
    }

    private func url(for sessionID: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased()).jbt")
    }

    private func migrateLegacyIfPresent() -> [SessionDocument]? {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let decoded = try JSONDecoder().decode(CatalogData.self, from: data)

            let documents = decoded.sessions.map { session in
                let tapes = decoded.tapes.filter { $0.sessionID == session.id }
                let links = decoded.sessionGear.filter { $0.sessionID == session.id }
                let linkedGearIDs = Set(links.map { $0.gearID })
                let gear = decoded.gear.filter { linkedGearIDs.contains($0.id) }
                let media = decoded.media.filter { $0.sessionID == session.id }

                return SessionDocument(
                    name: session.title,
                    session: session,
                    tapes: tapes,
                    gear: gear,
                    sessionGear: links,
                    media: media,
                    presets: []
                )
            }

            for doc in documents {
                saveSessionDocument(doc)
            }

            return documents
        } catch {
            print("[JBTStore] legacy migration failed: \(error)")
            return nil
        }
    }

    private func seedDocument() -> SessionDocument {
        let session = SessionRecord(
            id: UUID(),
            title: "Basement Burn-In",
            date: "2026-03-13",
            location: "Brooklyn",
            notes: "First pass through dirty chain"
        )

        let gearA = GearRecord(id: UUID(), name: "Panasonic AG-1980")
        let gearB = GearRecord(id: UUID(), name: "Video Toaster")

        let sessionGear = [
            SessionGearRecord(id: UUID(), sessionID: session.id, gearID: gearA.id, notes: "Deck A"),
            SessionGearRecord(id: UUID(), sessionID: session.id, gearID: gearB.id, notes: "Feedback bus")
        ]

        return SessionDocument(
            name: session.title,
            session: session,
            tapes: [
                TapeRecord(
                    sessionID: session.id,
                    tapeID: "T-001",
                    format: "VHS",
                    label: "BurnIn_A",
                    storageLocation: "Shelf C2",
                    notes: "Tracking drifts around 07:33"
                )
            ],
            gear: [gearA, gearB],
            sessionGear: sessionGear,
            media: [
                MediaRecord(
                    id: UUID(),
                    sessionID: session.id,
                    filePath: "/Volumes/GLITCH/BasementBurnIn/take01.mov",
                    kind: "video",
                    checksum: "sha256:demo",
                    duration: 182.4,
                    width: 1920,
                    height: 1080,
                    codec: "prores",
                    createdAt: "2026-03-13T21:14:00Z",
                    notes: "Best color break",
                    thumbnailPath: "/Volumes/GLITCH/BasementBurnIn/take01.jpg"
                )
            ],
            presets: []
        )
    }
}
