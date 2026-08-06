import AppKit
import Foundation

struct Snippet: Codable, Identifiable, Hashable {
    let id: UUID
    var label: String?
    var text: String

    enum CodingKeys: String, CodingKey {
        case label
        case text
    }

    init(label: String?, text: String) {
        id = UUID()
        self.label = label
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label)
        text = try container.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let label, !label.isEmpty {
            try container.encode(label, forKey: .label)
        }
        try container.encode(text, forKey: .text)
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var errorMessage: String?

    init() {
        reload()
    }

    func reload() {
        do {
            let url = try ensureFileExists()
            let data = try Data(contentsOf: url)
            snippets = try JSONDecoder().decode([Snippet].self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось прочитать snippets.json"
            NSLog("TopNest: не удалось прочитать заготовки: %@", error.localizedDescription)
        }
    }

    @discardableResult
    func add(label: String, text: String) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }
        guard readLatestBeforeEditing() else { return false }

        snippets.insert(
            Snippet(label: cleanLabel.isEmpty ? nil : cleanLabel, text: cleanText),
            at: 0
        )
        return save()
    }

    func remove(_ snippet: Snippet) {
        guard readLatestBeforeEditing() else { return }
        if let index = snippets.firstIndex(where: {
            $0.label == snippet.label && $0.text == snippet.text
        }) {
            snippets.remove(at: index)
            _ = save()
        }
    }

    func copy(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.text, forType: .string)
    }

    func revealFile() {
        do {
            let url = try ensureFileExists()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = "Не удалось открыть snippets.json"
        }
    }

    private func readLatestBeforeEditing() -> Bool {
        do {
            let url = try ensureFileExists()
            let data = try Data(contentsOf: url)
            snippets = try JSONDecoder().decode([Snippet].self, from: data)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Файл повреждён — исправьте JSON перед записью"
            return false
        }
    }

    private func ensureFileExists() throws -> URL {
        let url = try AppStorage.file(named: "snippets.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("[]\n".utf8).write(to: url, options: .atomic)
        }
        return url
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let url = try AppStorage.file(named: "snippets.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(snippets)
            try data.write(to: url, options: .atomic)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Не удалось сохранить snippets.json"
            return false
        }
    }
}
