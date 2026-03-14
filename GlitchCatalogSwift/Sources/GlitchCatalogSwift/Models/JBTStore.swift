import Foundation

final class JBTStore {
    private let fileURL: URL

    init(filename: String = "catalog_data.jbt") {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = docsDir.appendingPathComponent(filename)
    }

    func load() -> CatalogData {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(CatalogData.self, from: data)
            return decoded
        } catch {
            let seeded = seedData()
            save(seeded)
            return seeded
        }
    }

    func save(_ data: CatalogData) {
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: [.atomic])
        } catch {
            print("[JBTStore] save error: \(error)")
        }
    }

    private func seedData() -> CatalogData {
        let session = SessionRecord(
            id: UUID(),
            title: "Basement Burn-In",
            date: "2026-03-13",
            location: "Brooklyn",
            notes: "First pass through dirty chain"
        )

        let gearA = GearRecord(id: UUID(), name: "Panasonic AG-1980")
        let gearB = GearRecord(id: UUID(), name: "Video Toaster")

        return CatalogData(
            sessions: [session],
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
            sessionGear: [
                SessionGearRecord(id: UUID(), sessionID: session.id, gearID: gearA.id, notes: "Deck A"),
                SessionGearRecord(id: UUID(), sessionID: session.id, gearID: gearB.id, notes: "Feedback bus")
            ],
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
            ]
        )
    }
}
