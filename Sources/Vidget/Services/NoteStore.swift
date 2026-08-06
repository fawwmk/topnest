import AppKit
import Foundation

struct QuickNote: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var modifiedAt: Date

    var title: String {
        text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? "Новая заметка"
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [QuickNote] = []
    @Published var selectedID: QuickNote.ID?

    private var saveTask: Task<Void, Never>?

    init() {
        load()
    }

    var selectedNote: QuickNote? {
        guard let selectedID else { return nil }
        return notes.first(where: { $0.id == selectedID })
    }

    func ensureDraft() {
        if selectedID == nil || !notes.contains(where: { $0.id == selectedID }) {
            if let first = notes.first {
                selectedID = first.id
            } else {
                createNote()
            }
        }
    }

    func createNote() {
        let note = QuickNote(id: UUID(), text: "", modifiedAt: Date())
        notes.insert(note, at: 0)
        selectedID = note.id
    }

    func select(_ note: QuickNote) {
        selectedID = note.id
    }

    func updateSelectedText(_ text: String) {
        guard let selectedID,
              let index = notes.firstIndex(where: { $0.id == selectedID }) else { return }
        notes[index].text = text
        notes[index].modifiedAt = Date()
        scheduleSave()
    }

    func copySelected() {
        guard let note = selectedNote, !note.text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.text, forType: .string)
    }

    func deleteSelected() {
        guard let selectedID else { return }
        notes.removeAll { $0.id == selectedID }
        self.selectedID = notes.first?.id
        if notes.isEmpty {
            createNote()
        }
        saveImmediately()
    }

    func removeEmptyDrafts() {
        let emptyIDs = Set(notes.filter {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.id))
        guard !emptyIDs.isEmpty else {
            saveImmediately()
            return
        }
        notes.removeAll { emptyIDs.contains($0.id) }
        if let selectedID, emptyIDs.contains(selectedID) {
            self.selectedID = notes.first?.id
        }
        saveImmediately()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func load() {
        do {
            let url = try AppStorage.file(named: "notes.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([QuickNote].self, from: data)
            selectedID = notes.first?.id
        } catch {
            NSLog("TopNest: не удалось прочитать заметки: %@", error.localizedDescription)
        }
    }

    private func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let url = try AppStorage.file(named: "notes.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("TopNest: не удалось сохранить заметки: %@", error.localizedDescription)
        }
    }
}
