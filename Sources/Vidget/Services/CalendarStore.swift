import AppKit
import EventKit
import Foundation

enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let meetingURL: URL?

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }
}

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var access: CalendarAccess
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRequestingAccess = false

    private let eventStore = EKEventStore()
    private var eventObserver: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        observeChanges()
        if access == .granted {
            reload()
        }
    }

    func requestAccess() async {
        guard access == .notDetermined, !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            access = granted ? .granted : .denied
            if granted {
                reload()
            }
        } catch {
            access = Self.currentAccess()
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        access = Self.currentAccess()
        guard access == .granted else {
            entries = []
            return
        }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)

        entries = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEntry(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                        ?? "Без названия",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarName: event.calendar.title,
                    meetingURL: Self.meetingURL(in: event)
                )
            }
        errorMessage = nil
    }

    func join(_ entry: CalendarEntry) {
        guard let meetingURL = entry.meetingURL else { return }
        NSWorkspace.shared.open(meetingURL)
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeChanges() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .fullAccess, .authorized:
            .granted
        case .denied, .restricted, .writeOnly:
            .denied
        @unknown default:
            .denied
        }
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, isMeetingURL(url) {
            return url
        }

        let source = [event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: "\n")
        guard !source.isEmpty,
              let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else { return nil }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in detector.matches(in: source, options: [], range: range) {
            if let url = match.url, isMeetingURL(url) {
                return url
            }
        }
        return nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return [
            "zoom.us",
            "meet.google.com",
            "teams.microsoft.com",
            "teams.live.com",
            "webex.com",
            "whereby.com",
            "meet.jit.si",
            "telemost.yandex.ru",
            "discord.com",
            "discord.gg"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
