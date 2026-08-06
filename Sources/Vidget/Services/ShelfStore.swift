import AppKit
import Foundation

struct ShelfItem: Codable, Identifiable, Hashable {
    let id: UUID
    let path: String
    let addedAt: Date

    init(url: URL) {
        id = UUID()
        path = url.standardizedFileURL.path
        addedAt = Date()
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<ShelfItem.ID> = []

    init() {
        load()
    }

    func add(_ urls: [URL]) {
        let normalized = urls
            .filter({ $0.isFileURL })
            .map({ $0.standardizedFileURL })

        guard !normalized.isEmpty else { return }
        let incomingPaths = Set(normalized.map(\.path))
        items.removeAll { incomingPaths.contains($0.path) }
        items.insert(contentsOf: normalized.map(ShelfItem.init), at: 0)
        save()
    }

    func toggleSelection(_ item: ShelfItem, extending: Bool) {
        if extending {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else {
            selection = [item.id]
        }
    }

    func remove(_ item: ShelfItem) {
        selection.remove(item.id)
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeSelection() {
        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
        save()
    }

    private func load() {
        do {
            let url = try AppStorage.file(named: "shelf.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ShelfItem].self, from: data)
        } catch {
            NSLog("TopNest: не удалось прочитать полку: %@", error.localizedDescription)
        }
    }

    private func save() {
        do {
            let url = try AppStorage.file(named: "shelf.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("TopNest: не удалось сохранить полку: %@", error.localizedDescription)
        }
    }
}
