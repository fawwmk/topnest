import AppKit
import Foundation

struct ClipboardEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let copiedAt: Date

    init(text: String) {
        id = UUID()
        self.text = text
        copiedAt = Date()
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let pasteboard = NSPasteboard.general
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
        load()
        startMonitoring()
    }

    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        promote(text: entry.text)
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func pauseMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func resumeMonitoring() {
        guard timer == nil else { return }
        poll()
        startMonitoring()
    }

    private func startMonitoring() {
        guard timer == nil else { return }
        let nextTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        nextTimer.tolerance = 0.1
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if pasteboard.pasteboardItems?.contains(where: { $0.types.contains(concealedType) }) == true {
            return
        }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return }

        promote(text: text)
    }

    private func promote(text: String) {
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text), at: 0)
        if entries.count > 40 {
            entries.removeLast(entries.count - 40)
        }
        save()
    }

    private func load() {
        var sourceURL: URL?
        do {
            let url = try AppStorage.file(named: "clipboard.json")
            sourceURL = url
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([ClipboardEntry].self, from: data)
        } catch {
            if let sourceURL {
                AppStorage.preserveCorruptFile(at: sourceURL)
            }
            entries = []
            NSLog("TopNest: не удалось прочитать буфер: %@", error.localizedDescription)
        }
    }

    private func save() {
        do {
            let url = try AppStorage.file(named: "clipboard.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("TopNest: не удалось сохранить буфер: %@", error.localizedDescription)
        }
    }
}
