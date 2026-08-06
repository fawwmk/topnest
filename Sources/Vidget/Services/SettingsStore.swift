import Foundation
import ServiceManagement

enum PrivateContentSection: String {
    case clipboard
    case snippets
    case calendar
    case notes
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var privacyModeEnabled: Bool {
        didSet { defaults.set(privacyModeEnabled, forKey: Keys.privacyMode) }
    }
    @Published var hidesClipboard: Bool {
        didSet { defaults.set(hidesClipboard, forKey: Keys.clipboard) }
    }
    @Published var hidesSnippets: Bool {
        didSet { defaults.set(hidesSnippets, forKey: Keys.snippets) }
    }
    @Published var hidesCalendar: Bool {
        didSet { defaults.set(hidesCalendar, forKey: Keys.calendar) }
    }
    @Published var hidesNotes: Bool {
        didSet { defaults.set(hidesNotes, forKey: Keys.notes) }
    }
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var temporarilyRevealed: Set<String> = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let privacyMode = "TopNest.privacyModeEnabled"
        static let clipboard = "TopNest.privacy.hidesClipboard"
        static let snippets = "TopNest.privacy.hidesSnippets"
        static let calendar = "TopNest.privacy.hidesCalendar"
        static let notes = "TopNest.privacy.hidesNotes"
    }

    init() {
        privacyModeEnabled = defaults.bool(forKey: Keys.privacyMode)
        hidesClipboard = Self.storedBool(defaults, key: Keys.clipboard, fallback: true)
        hidesSnippets = Self.storedBool(defaults, key: Keys.snippets, fallback: true)
        hidesCalendar = Self.storedBool(defaults, key: Keys.calendar, fallback: true)
        hidesNotes = Self.storedBool(defaults, key: Keys.notes, fallback: true)
        refreshLaunchAtLoginStatus()
    }

    func isHidden(_ section: PrivateContentSection, id: String) -> Bool {
        privacyModeEnabled && hides(section) && !temporarilyRevealed.contains(key(section, id))
    }

    func revealTemporarily(_ section: PrivateContentSection, id: String) {
        temporarilyRevealed.insert(key(section, id))
    }

    func resetTemporaryReveals() {
        temporarilyRevealed.removeAll()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = enabled
                ? "Не удалось включить запуск при входе"
                : "Не удалось выключить запуск при входе"
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func hides(_ section: PrivateContentSection) -> Bool {
        switch section {
        case .clipboard: hidesClipboard
        case .snippets: hidesSnippets
        case .calendar: hidesCalendar
        case .notes: hidesNotes
        }
    }

    private func key(_ section: PrivateContentSection, _ id: String) -> String {
        section.rawValue + ":" + id
    }

    private static func storedBool(
        _ defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}
