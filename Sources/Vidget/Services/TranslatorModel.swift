import AppKit
import Foundation
import NaturalLanguage
@preconcurrency import Translation

enum SupportedTranslationLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"
    case italian = "it"

    var id: Self { self }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        case .italian: "Italiano"
        }
    }

    var shortName: String { rawValue.uppercased() }
}

struct TranslationPair: Equatable {
    let source: SupportedTranslationLanguage
    let target: SupportedTranslationLanguage
}

enum TranslationAvailabilityState: Equatable {
    case idle
    case checking
    case preparing
    case ready
    case unsupported
    case failed(String)
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var sourceText = ""
    @Published var selectedSource: SupportedTranslationLanguage?
    @Published var selectedTarget: SupportedTranslationLanguage = .russian
    @Published private(set) var detectedSource: SupportedTranslationLanguage = .english
    @Published private(set) var activePair: TranslationPair?
    @Published private(set) var translatedText = ""
    @Published private(set) var availability: TranslationAvailabilityState = .idle
    @Published private(set) var isTranslating = false
    @Published private(set) var isPreparingLanguages = false

    private let languageAvailability = LanguageAvailability()

    var sourceHeader: String {
        if let selectedSource {
            return selectedSource.displayName
        }
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Авто"
        }
        return "Авто · \(detectedSource.shortName)"
    }

    func prepare(text: String) async -> TranslationPair? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            resetOutput()
            return nil
        }

        let source = selectedSource ?? Self.detectLanguage(in: cleanText)
        detectedSource = source
        if selectedTarget == source {
            selectedTarget = Self.fallbackTarget(for: source)
        }
        let pair = TranslationPair(source: source, target: selectedTarget)
        activePair = pair

        translatedText = ""
        availability = .checking
        let status = await languageAvailability.status(
            from: pair.source.localeLanguage,
            to: pair.target.localeLanguage
        )
        guard sourceText.trimmingCharacters(in: .whitespacesAndNewlines) == cleanText else {
            return nil
        }

        switch status {
        case .installed:
            availability = .ready
            return pair
        case .supported:
            // The pair is supported, but its on-device models still need to be
            // downloaded. TranslationSession.prepareTranslation() owns that flow.
            availability = .preparing
            return pair
        case .unsupported:
            isPreparingLanguages = false
            isTranslating = false
            availability = .unsupported
            return nil
        @unknown default:
            isPreparingLanguages = false
            isTranslating = false
            availability = .failed("Не удалось проверить языковой пакет")
            return nil
        }
    }

    func chooseSource(_ language: SupportedTranslationLanguage?) {
        selectedSource = language
        if let language, language == selectedTarget {
            selectedTarget = Self.fallbackTarget(for: language)
        }
    }

    func chooseTarget(_ language: SupportedTranslationLanguage) {
        selectedTarget = language
        if selectedSource == language {
            selectedSource = nil
        }
    }

    func beginLanguagePreparation(sourceText: String, pair: TranslationPair?) -> Bool {
        guard self.sourceText == sourceText, activePair == pair else { return false }
        isPreparingLanguages = true
        isTranslating = false
        availability = .preparing
        return true
    }

    func beginTranslation(sourceText: String, pair: TranslationPair?) -> Bool {
        guard self.sourceText == sourceText, activePair == pair else { return false }
        isPreparingLanguages = false
        isTranslating = true
        availability = .ready
        return true
    }

    func applyTranslation(_ result: String, sourceText: String, pair: TranslationPair?) {
        guard self.sourceText == sourceText, activePair == pair else { return }
        translatedText = result
        isPreparingLanguages = false
        isTranslating = false
        availability = .ready
    }

    func applyError(_ error: Error, sourceText: String, pair: TranslationPair?) {
        guard self.sourceText == sourceText, activePair == pair else { return }
        translatedText = ""
        isPreparingLanguages = false
        isTranslating = false
        availability = .failed(error.localizedDescription)
    }

    func applyCancellation(sourceText: String, pair: TranslationPair?) {
        guard self.sourceText == sourceText, activePair == pair else { return }
        isPreparingLanguages = false
        isTranslating = false
        availability = .idle
    }

    func resetOutput() {
        translatedText = ""
        isPreparingLanguages = false
        isTranslating = false
        availability = .idle
        activePair = nil
    }

    func copyResult() {
        guard !translatedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }

    func openLanguageSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Localization-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    static func detectLanguage(in text: String) -> SupportedTranslationLanguage {
        if text.unicodeScalars.contains(where: { (0x0400...0x052F).contains($0.value) }) {
            return .russian
        }

        switch NLLanguageRecognizer.dominantLanguage(for: text) {
        case NLLanguage.italian:
            return SupportedTranslationLanguage.italian
        case NLLanguage.russian:
            return SupportedTranslationLanguage.russian
        default:
            return SupportedTranslationLanguage.english
        }
    }

    private static func fallbackTarget(
        for source: SupportedTranslationLanguage
    ) -> SupportedTranslationLanguage {
        switch source {
        case .russian: .english
        case .english, .italian: .russian
        }
    }
}
