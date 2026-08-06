import AppKit
@preconcurrency import Foundation

struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String
    let album: String
    let sourceName: String
    let sourceBundleIdentifier: String
    let contentIdentifier: String?
    let duration: Double
    let elapsed: Double
    let playbackRate: Double
    let isPlaying: Bool
    let artworkData: Data?
    let receivedAt: Date

    func estimatedElapsed(at date: Date) -> Double {
        let additional = isPlaying
            ? max(0, date.timeIntervalSince(receivedAt)) * max(0, playbackRate)
            : 0
        return min(max(0, elapsed + additional), max(0, duration))
    }
}

struct PlaybackHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var sourceName: String
    var sourceBundleIdentifier: String?
    var contentIdentifier: String?
    var duration: Double
    var lastPosition: Double
    var artworkData: Data?
    var lastSeen: Date

    func matches(_ snapshot: NowPlayingSnapshot) -> Bool {
        let sameSource: Bool
        if let sourceBundleIdentifier,
           !sourceBundleIdentifier.isEmpty,
           !snapshot.sourceBundleIdentifier.isEmpty {
            sameSource = sourceBundleIdentifier == snapshot.sourceBundleIdentifier
        } else {
            sameSource = sourceName.caseInsensitiveCompare(snapshot.sourceName) == .orderedSame
        }
        return sameSource
            && title.caseInsensitiveCompare(snapshot.title) == .orderedSame
            && artist.caseInsensitiveCompare(snapshot.artist) == .orderedSame
    }
}

enum MediaControllerStatus: Equatable {
    case loading
    case empty
    case ready
    case unavailable(String)
}

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var status: MediaControllerStatus = .loading
    @Published private(set) var history: [PlaybackHistoryEntry] = []
    @Published var automaticallyResumesPlayback: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyResumesPlayback,
                forKey: Self.autoResumeDefaultsKey
            )
        }
    }

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var retryCount = 0
    private var restartTask: Task<Void, Never>?
    private var isStopping = false
    private var autoResumeAttempted = false
    private var pendingResumeEntry: PlaybackHistoryEntry?
    private var pendingResumeTimeoutTask: Task<Void, Never>?
    private var sourceLaunchProcess: Process?

    private static let autoResumeDefaultsKey = "TopNest.automaticallyResumesPlayback"
    private static let historyLimit = 20

    init() {
        let storedPreference = UserDefaults.standard.object(
            forKey: Self.autoResumeDefaultsKey
        ) as? Bool
        automaticallyResumesPlayback = storedPreference ?? true
        loadHistory()
        start()
    }

    func retry() {
        retryCount = 0
        isStopping = false
        stopProcess()
        start()
    }

    func togglePlayback() {
        guard let snapshot else {
            resumeLastTrack()
            return
        }
        if !isSourceRunning(snapshot.sourceBundleIdentifier),
           let entry = history.first(where: { $0.matches(snapshot) }) {
            pendingResumeTimeoutTask?.cancel()
            pendingResumeEntry = entry
            playInSource(of: entry)
            return
        }
        send(command: "toggle", bundleIdentifier: snapshot.sourceBundleIdentifier)
    }

    func previous() {
        send(command: "previous", bundleIdentifier: snapshot?.sourceBundleIdentifier)
    }

    func next() {
        send(command: "next", bundleIdentifier: snapshot?.sourceBundleIdentifier)
    }

    func seek(to seconds: Double) {
        send(command: "seek", value: max(0, seconds))
    }

    func resumeLastTrack() {
        guard let last = history.first else { return }
        pendingResumeTimeoutTask?.cancel()
        pendingResumeEntry = last
        if let snapshot,
           last.matches(snapshot),
           isSourceRunning(snapshot.sourceBundleIdentifier) {
            pendingResumeEntry = nil
            send(command: "seek", value: last.lastPosition)
            if !snapshot.isPlaying {
                send(command: "play", bundleIdentifier: snapshot.sourceBundleIdentifier)
            }
        } else {
            playInSource(of: last)
        }
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func stop() {
        persistCurrentPosition()
        isStopping = true
        restartTask?.cancel()
        restartTask = nil
        pendingResumeTimeoutTask?.cancel()
        pendingResumeTimeoutTask = nil
        if let sourceLaunchProcess, sourceLaunchProcess.isRunning {
            sourceLaunchProcess.terminate()
        }
        sourceLaunchProcess = nil
        stopProcess()
    }

    private func start() {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            status = .unavailable("Системный медиапомощник недоступен")
            return
        }
        guard let helperURL = Bundle.main.url(
            forResource: "TopNestMediaHelper",
            withExtension: "dylib"
        ) else {
            status = .unavailable("Модуль системного плеера не найден")
            return
        }

        status = .loading
        isStopping = false
        autoResumeAttempted = false
        pendingResumeEntry = nil
        pendingResumeTimeoutTask?.cancel()
        pendingResumeTimeoutTask = nil
        outputBuffer.removeAll(keepingCapacity: true)

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e",
            "use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0x01); die DynaLoader::dl_error() unless $h; sleep 2147483647;",
            helperURL.path
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                self?.consume(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                guard let self, !message.isEmpty, self.snapshot == nil else { return }
                self.status = .unavailable(message)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.helperDidTerminate()
            }
        }

        do {
            try process.run()
            self.process = process
            inputHandle = inputPipe.fileHandleForWriting
            outputHandle = outputPipe.fileHandleForReading
        } catch {
            status = .unavailable("Не удалось запустить медиапомощник")
            scheduleRestart()
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            decode(Data(line))
        }
    }

    private func decode(_ data: Data) {
        guard let message = try? JSONDecoder().decode(HelperMessage.self, from: data) else {
            return
        }
        switch message.type {
        case "state":
            retryCount = 0
            guard let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                snapshot = nil
                status = .empty
                attemptAutoResumeIfNeeded(current: nil)
                return
            }
            let nextSnapshot = NowPlayingSnapshot(
                title: title,
                artist: message.artist ?? "",
                album: message.album ?? "",
                sourceName: message.source ?? "",
                sourceBundleIdentifier: message.sourceBundleIdentifier ?? "",
                contentIdentifier: message.contentIdentifier,
                duration: message.duration ?? 0,
                elapsed: message.elapsed ?? 0,
                playbackRate: message.playbackRate ?? (message.isPlaying == true ? 1 : 0),
                isPlaying: message.isPlaying ?? false,
                artworkData: message.artworkBase64.flatMap { Data(base64Encoded: $0) },
                receivedAt: Date()
            )
            snapshot = nextSnapshot
            status = .ready
            record(nextSnapshot)
            completePendingResumeIfPossible(with: nextSnapshot)
            attemptAutoResumeIfNeeded(current: nextSnapshot)
        case "error":
            snapshot = nil
            status = .unavailable(message.message ?? "Системный плеер недоступен")
        default:
            break
        }
    }

    private func send(
        command: String,
        value: Double? = nil,
        bundleIdentifier: String? = nil
    ) {
        guard let inputHandle else { return }
        let target = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let payload = HelperCommand(
            command: command,
            value: value,
            bundleIdentifier: target
        )
        guard var data = try? JSONEncoder().encode(payload) else { return }
        data.append(0x0A)
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            status = .unavailable("Связь с медиапомощником потеряна")
        }
    }

    private func attemptAutoResumeIfNeeded(current: NowPlayingSnapshot?) {
        guard automaticallyResumesPlayback,
              !autoResumeAttempted,
              let last = history.first else { return }
        autoResumeAttempted = true
        pendingResumeEntry = last
        if let current, isSourceRunning(current.sourceBundleIdentifier) {
            guard last.matches(current) else {
                pendingResumeEntry = nil
                return
            }
            pendingResumeEntry = nil
            send(command: "seek", value: last.lastPosition)
            if !current.isPlaying {
                send(command: "play", bundleIdentifier: current.sourceBundleIdentifier)
            }
        } else {
            playInSource(of: last)
        }
    }

    private func completePendingResumeIfPossible(with current: NowPlayingSnapshot) {
        guard let pendingResumeEntry else { return }
        guard pendingResumeEntry.matches(current) else { return }
        self.pendingResumeEntry = nil
        pendingResumeTimeoutTask?.cancel()
        pendingResumeTimeoutTask = nil
        send(command: "seek", value: pendingResumeEntry.lastPosition)
        if !current.isPlaying {
            send(command: "play", bundleIdentifier: current.sourceBundleIdentifier)
        }
    }

    private func playInSource(of entry: PlaybackHistoryEntry) {
        guard let bundleIdentifier = entry.sourceBundleIdentifier,
              !bundleIdentifier.isEmpty else {
            status = .unavailable("Для этой старой записи источник ещё не сохранён")
            pendingResumeEntry = nil
            return
        }

        let deepLink = fallbackDeepLink(for: entry)
        if deepLink == nil,
           let runningApplication = NSRunningApplication.runningApplications(
               withBundleIdentifier: bundleIdentifier
           ).first {
            runningApplication.activate()
            send(command: "play", bundleIdentifier: bundleIdentifier)
            beginResumeTimeout(for: entry)
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            status = .unavailable("Приложение, где играл трек, больше не найдено")
            pendingResumeEntry = nil
            return
        }
        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launchProcess.arguments = [deepLink?.absoluteString ?? applicationURL.path]
        launchProcess.environment = sanitizedLaunchEnvironment()
        launchProcess.terminationHandler = { [weak self, weak launchProcess] process in
            Task { @MainActor [weak self, weak launchProcess] in
                guard let self else { return }
                if self.sourceLaunchProcess === launchProcess {
                    self.sourceLaunchProcess = nil
                }
                guard process.terminationStatus != 0 else { return }
                self.status = .unavailable("Не удалось открыть источник последнего трека")
                self.pendingResumeEntry = nil
            }
        }
        do {
            try launchProcess.run()
            sourceLaunchProcess = launchProcess
            beginResumeTimeout(for: entry)
        } catch {
            status = .unavailable("Не удалось открыть источник последнего трека")
            pendingResumeEntry = nil
        }
    }

    private func fallbackDeepLink(for entry: PlaybackHistoryEntry) -> URL? {
        guard entry.sourceBundleIdentifier == "ru.yandex.desktop.music" else {
            return nil
        }
        if let exactURL = yandexDeepLink(from: entry.contentIdentifier) {
            return exactURL
        }
        let searchText = [entry.artist, entry.title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !searchText.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "yandexmusic"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "text", value: searchText)]
        return components.url
    }

    private func yandexDeepLink(from identifier: String?) -> URL? {
        guard let identifier, !identifier.isEmpty else { return nil }
        if identifier.hasPrefix("yandexmusic://") {
            return URL(string: identifier)
        }
        if let url = URL(string: identifier),
           let host = url.host,
           host.contains("yandex"),
           !url.path.isEmpty {
            var value = "yandexmusic://" + url.path.dropFirst()
            if let query = url.query, !query.isEmpty {
                value += "?" + query
            }
            return URL(string: value)
        }
        if identifier.allSatisfy(\.isNumber) {
            return URL(string: "yandexmusic://track/\(identifier)")
        }
        return nil
    }

    private func isSourceRunning(_ bundleIdentifier: String) -> Bool {
        !bundleIdentifier.isEmpty
            && !NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).isEmpty
    }

    private func sanitizedLaunchEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("ELECTRON_")
                && !key.hasPrefix("VSCODE_")
                && key != "NODE_OPTIONS"
        }
    }

    private func beginResumeTimeout(for entry: PlaybackHistoryEntry) {
        pendingResumeTimeoutTask?.cancel()
        pendingResumeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  let self,
                  self.pendingResumeEntry?.id == entry.id else { return }
            if let bundleIdentifier = entry.sourceBundleIdentifier {
                self.send(command: "play", bundleIdentifier: bundleIdentifier)
            }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  self.pendingResumeEntry?.id == entry.id else { return }
            self.pendingResumeEntry = nil
            self.pendingResumeTimeoutTask = nil
            self.status = .unavailable(
                "Источник открылся, но не восстановил последний трек"
            )
        }
    }

    private func record(_ snapshot: NowPlayingSnapshot) {
        let now = Date()
        let position = snapshot.estimatedElapsed(at: now)
        let retainedArtwork = snapshot.artworkData.flatMap { data in
            data.count <= 1_000_000 ? data : nil
        }
        let existingIndex = history.firstIndex { $0.matches(snapshot) }
        var entry = existingIndex.map { history.remove(at: $0) } ?? PlaybackHistoryEntry(
            id: UUID(),
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            sourceName: snapshot.sourceName,
            sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
            contentIdentifier: snapshot.contentIdentifier,
            duration: snapshot.duration,
            lastPosition: position,
            artworkData: retainedArtwork,
            lastSeen: now
        )
        entry.title = snapshot.title
        entry.artist = snapshot.artist
        entry.album = snapshot.album
        entry.sourceName = snapshot.sourceName
        entry.sourceBundleIdentifier = snapshot.sourceBundleIdentifier
        entry.contentIdentifier = snapshot.contentIdentifier ?? entry.contentIdentifier
        entry.duration = snapshot.duration
        entry.lastPosition = position
        entry.artworkData = retainedArtwork ?? entry.artworkData
        entry.lastSeen = now
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        saveHistory()
    }

    private func persistCurrentPosition() {
        guard let snapshot else { return }
        record(snapshot)
    }

    private func loadHistory() {
        guard let url = try? AppStorage.file(named: "playback-history.json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                [PlaybackHistoryEntry].self,
                from: data
              ) else { return }
        history = Array(decoded.prefix(Self.historyLimit))
    }

    private func saveHistory() {
        guard let url = try? AppStorage.file(named: "playback-history.json") else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func helperDidTerminate() {
        process = nil
        inputHandle = nil
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        guard !isStopping else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard retryCount < 3, restartTask == nil else {
            status = .unavailable("Системный плеер временно недоступен")
            return
        }
        retryCount += 1
        let delay = retryCount
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.restartTask = nil
            self.start()
        }
    }

    private func stopProcess() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        try? inputHandle?.close()
        inputHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }
}

private struct HelperMessage: Decodable {
    let type: String
    let message: String?
    let title: String?
    let artist: String?
    let album: String?
    let source: String?
    let sourceBundleIdentifier: String?
    let contentIdentifier: String?
    let duration: Double?
    let elapsed: Double?
    let playbackRate: Double?
    let isPlaying: Bool?
    let artworkBase64: String?
}

private struct HelperCommand: Encodable {
    let command: String
    let value: Double?
    let bundleIdentifier: String?
}
