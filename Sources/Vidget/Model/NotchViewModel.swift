import SwiftUI

enum VidgetTab: String, CaseIterable, Identifiable {
    case player
    case shelf
    case clipboard
    case snippets
    case calendar
    case translate
    case notes

    var id: Self { self }

    var title: String {
        switch self {
        case .player: "Музыка"
        case .shelf: "Полка"
        case .clipboard: "Буфер"
        case .snippets: "Заготовки"
        case .calendar: "Календарь"
        case .translate: "Перевод"
        case .notes: "Заметки"
        }
    }

    var symbol: String {
        switch self {
        case .player: "waveform"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .snippets: "text.badge.plus"
        case .calendar: "calendar"
        case .translate: "character.book.closed"
        case .notes: "note.text"
        }
    }

    var subtitle: String {
        switch self {
        case .player: "Системное воспроизведение"
        case .shelf: "Перетащите сюда файлы"
        case .clipboard: "Последние копирования"
        case .snippets: "Постоянные фрагменты текста"
        case .calendar: "Ближайшие встречи"
        case .translate: "Русский · English · Italiano"
        case .notes: "Быстрые временные записи"
        }
    }

    var acceptsKeyboardInput: Bool {
        switch self {
        case .snippets, .translate, .notes: true
        default: false
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var selectedTab: VidgetTab = .player {
        didSet {
            if oldValue == .notes, selectedTab != .notes {
                noteStore.removeEmptyDrafts()
            }
            if selectedTab == .notes {
                noteStore.ensureDraft()
            }
            if selectedTab == .snippets {
                snippetStore.reload()
            }
            if selectedTab == .calendar {
                calendarStore.reload()
            }
        }
    }
    let shelfStore = ShelfStore()
    let clipboardStore = ClipboardStore()
    let snippetStore = SnippetStore()
    let noteStore = NoteStore()
    let calendarStore = CalendarStore()
    let translator = TranslatorModel()
    let screenTextCapture = ScreenTextCapture()

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        if !expanded, selectedTab == .notes {
            noteStore.removeEmptyDrafts()
        }
        let animation: Animation = expanded
            ? .easeOut(duration: 0.16)
            : .easeInOut(duration: 0.2)
        withAnimation(animation) {
            isExpanded = expanded
        }
    }
}
