import AppKit
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
    @Published var savesCapturedImages: Bool {
        didSet { defaults.set(savesCapturedImages, forKey: Keys.savesCapturedImages) }
    }
    @Published private(set) var capturedImagesDirectoryPath: String
    @Published private(set) var capturedImagesError: String?
    @Published private(set) var temporarilyRevealed: Set<String> = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let privacyMode = "TopNest.privacyModeEnabled"
        static let clipboard = "TopNest.privacy.hidesClipboard"
        static let snippets = "TopNest.privacy.hidesSnippets"
        static let calendar = "TopNest.privacy.hidesCalendar"
        static let notes = "TopNest.privacy.hidesNotes"
        static let savesCapturedImages = "TopNest.capture.savesImages"
        static let capturedImagesDirectory = "TopNest.capture.directory"
    }

    init() {
        privacyModeEnabled = defaults.bool(forKey: Keys.privacyMode)
        hidesClipboard = Self.storedBool(defaults, key: Keys.clipboard, fallback: true)
        hidesSnippets = Self.storedBool(defaults, key: Keys.snippets, fallback: true)
        hidesCalendar = Self.storedBool(defaults, key: Keys.calendar, fallback: true)
        hidesNotes = Self.storedBool(defaults, key: Keys.notes, fallback: true)
        savesCapturedImages = defaults.bool(forKey: Keys.savesCapturedImages)
        capturedImagesDirectoryPath = defaults.string(forKey: Keys.capturedImagesDirectory)
            ?? Self.defaultCapturedImagesDirectory.path
        refreshLaunchAtLoginStatus()
    }

    var capturedImagesDirectoryName: String {
        URL(fileURLWithPath: capturedImagesDirectoryPath).lastPathComponent
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

    func chooseCapturedImagesDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Папка для снимков TopNest"
        panel.prompt = "Выбрать"
        panel.message = "Снимки выделенной области будут сохраняться локально в эту папку."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: capturedImagesDirectoryPath)

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        capturedImagesDirectoryPath = directory.path
        defaults.set(directory.path, forKey: Keys.capturedImagesDirectory)
        capturedImagesError = nil
    }

    func openCapturedImagesDirectory() {
        let directory = URL(fileURLWithPath: capturedImagesDirectoryPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            capturedImagesError = nil
            NSWorkspace.shared.open(directory)
        } catch {
            capturedImagesError = "Не удалось открыть папку снимков"
        }
    }

    func saveCapturedImage(_ image: CGImage) {
        guard savesCapturedImages else { return }
        let directory = URL(fileURLWithPath: capturedImagesDirectoryPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let baseName = "TopNest " + formatter.string(from: Date())
            let destination = availableCaptureURL(baseName: baseName, in: directory)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                capturedImagesError = "Не удалось подготовить снимок"
                return
            }
            try data.write(to: destination, options: .atomic)
            capturedImagesError = nil
        } catch {
            capturedImagesError = "Не удалось сохранить снимок"
        }
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

    private func availableCaptureURL(baseName: String, in directory: URL) -> URL {
        var suffix = 1
        var candidate = directory.appendingPathComponent(baseName + ".png")
        while FileManager.default.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).png")
        }
        return candidate
    }

    private static var defaultCapturedImagesDirectory: URL {
        let pictures = FileManager.default.urls(
            for: .picturesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("TopNest", isDirectory: true)
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
