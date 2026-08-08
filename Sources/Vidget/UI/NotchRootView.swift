import AppKit
import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedPanel(viewModel: viewModel)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
                        )
                    )
            } else {
                CollapsedNotch()
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(
            width: NotchGeometry.windowSize.width,
            height: NotchGeometry.windowSize.height,
            alignment: .top
        )
        .preferredColorScheme(.dark)
    }
}

private struct CollapsedNotch: View {
    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0
            )
            .fill(.black)

            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 34, height: 3)
                .offset(y: 5)
        }
        .frame(
            width: NotchGeometry.fallbackNotchSize.width,
            height: NotchGeometry.fallbackNotchSize.height
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TopNest")
        .accessibilityHint("Наведите курсор, чтобы открыть панель")
    }
}

private struct ExpandedPanel: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            TabRail(viewModel: viewModel, tabs: Array(VidgetTab.allCases.prefix(6)))

            Divider()
                .overlay(.white.opacity(0.07))
                .padding(.vertical, 18)

            TabContent(viewModel: viewModel, tab: viewModel.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(.white.opacity(0.07))
                .padding(.vertical, 18)

            TabRail(viewModel: viewModel, tabs: [.notes, .settings])
        }
        .frame(
            width: NotchGeometry.expandedSize.width,
            height: NotchGeometry.expandedSize.height
        )
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 0
            )
            .fill(Color(red: 0.035, green: 0.038, blue: 0.045))
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 28,
                        bottomTrailingRadius: 28,
                        topTrailingRadius: 0
                    )
                )
            }
        }
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 0
            )
            .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.shelfStore.add(urls)
            viewModel.selectedTab = .shelf
            return !urls.isEmpty
        } isTargeted: { targeted in
            guard targeted else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                viewModel.selectedTab = .shelf
            }
        }
    }
}

private struct TabRail: View {
    @ObservedObject var viewModel: NotchViewModel
    let tabs: [VidgetTab]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tabs) { tab in
                HoverTabButton(
                    tab: tab,
                    selected: viewModel.selectedTab == tab
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        viewModel.selectedTab = tab
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .frame(width: 72)
    }
}

private struct HoverTabButton: View {
    let tab: VidgetTab
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? .white : .white.opacity(0.5))
                .frame(width: 42, height: 30)
                .background(selected ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .scaleEffect(hovering ? 1.1 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
        .accessibilityLabel(tab.title)
        .accessibilityValue(selected ? "Выбрано" : "")
        .accessibilityHint(
            Text(verbatim: "Перейти на вкладку, Command \(tab.keyboardShortcut.character)")
        )
        .onHover { isHovering in
            hovering = isHovering
            hoverTask?.cancel()
            guard isHovering, !selected else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                action()
            }
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private struct TabContent: View {
    @ObservedObject var viewModel: NotchViewModel
    let tab: VidgetTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(tab.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Text("ПРОТОТИП")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.36))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.06), in: Capsule())
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 21)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .player:
            PlayerView(controller: viewModel.mediaController)
        case .shelf:
            ShelfView(store: viewModel.shelfStore)
        case .clipboard:
            ClipboardView(store: viewModel.clipboardStore, settings: viewModel.settingsStore)
        case .snippets:
            SnippetView(store: viewModel.snippetStore, settings: viewModel.settingsStore)
        case .calendar:
            CalendarView(store: viewModel.calendarStore, settings: viewModel.settingsStore)
        case .translate:
            TranslationView(
                model: viewModel.translator,
                screenCapture: viewModel.screenTextCapture
            )
        case .notes:
            NotesView(store: viewModel.noteStore, settings: viewModel.settingsStore)
        case .settings:
            SettingsView(store: viewModel.settingsStore)
        }
    }

    private var emptyMessage: String {
        switch tab {
        case .player: "Сейчас ничего не играет"
        case .shelf: "Перетащите файлы в панель"
        case .clipboard: "История буфера пока пуста"
        case .snippets: "Добавьте первую заготовку"
        case .calendar: "Подключите календарь"
        case .translate: "Введите текст для перевода"
        case .notes: "Создайте быструю заметку"
        case .settings: "Настройте TopNest"
        }
    }
}

private struct PlayerView: View {
    @ObservedObject var controller: MediaController
    @State private var isSeeking = false
    @State private var seekValue = 0.0
    @State private var showsHistory = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsHistory {
                historyContent
            } else {
                switch controller.status {
                case .loading:
                    playerStatus(symbol: "waveform", title: "Ищем активный источник…")
                case .empty:
                    if let last = controller.history.first {
                        lastTrackContent(last)
                    } else {
                        playerStatus(symbol: "waveform", title: "Сейчас ничего не играет")
                    }
                case .unavailable(let message):
                    VStack(spacing: 9) {
                        playerStatus(symbol: "exclamationmark.triangle", title: message)
                        Button("Повторить") { controller.retry() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.9))
                    }
                case .ready:
                    if let snapshot = controller.snapshot {
                        TimelineView(.periodic(from: .now, by: 0.5)) { context in
                            playerContent(snapshot, now: context.date)
                        }
                    } else {
                        playerStatus(symbol: "waveform", title: "Сейчас ничего не играет")
                    }
                }
            }

            if !controller.history.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsHistory.toggle()
                    }
                } label: {
                    Image(systemName: showsHistory ? "xmark" : "clock.arrow.circlepath")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 25, height: 25)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help(showsHistory ? "Вернуться к плееру" : "История треков")
                .accessibilityLabel(showsHistory ? "Вернуться к плееру" : "История треков")
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Недавние треки")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Label("Запуск только вручную", systemImage: "hand.tap")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.trailing, 32)
            }

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(controller.history.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 9) {
                            historyArtwork(entry)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Text([entry.artist, entry.sourceName]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.white.opacity(0.38))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.lastSeen, style: .relative)
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.25))
                            if index == 0 {
                                Button { controller.resumeLastTrack() } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .buttonStyle(.plain)
                                .help("Продолжить последний трек")
                                .accessibilityLabel("Продолжить последний трек")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Spacer()
                Button("Очистить историю") { controller.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.top, 8)
    }

    private func lastTrackContent(_ entry: PlaybackHistoryEntry) -> some View {
        HStack(spacing: 14) {
            historyArtwork(entry, size: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text("Последний трек")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.3))
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(entry.artist.isEmpty ? entry.sourceName : entry.artist)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Button {
                    controller.resumeLastTrack()
                } label: {
                    Label("Продолжить", systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.9))
            }
            Spacer()
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func playerContent(_ snapshot: NowPlayingSnapshot, now: Date) -> some View {
        let elapsed = snapshot.estimatedElapsed(at: now)

        HStack(spacing: 17) {
            artwork(snapshot)

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(snapshot.artist.isEmpty ? snapshot.album : snapshot.artist)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                    if !snapshot.sourceName.isEmpty {
                        Text(snapshot.sourceName.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.28))
                            .lineLimit(1)
                    }
                }

                if snapshot.duration > 0 {
                    VStack(spacing: 2) {
                        Slider(
                            value: Binding(
                                get: { isSeeking ? seekValue : elapsed },
                                set: { seekValue = $0 }
                            ),
                            in: 0...snapshot.duration,
                            onEditingChanged: { editing in
                                if editing {
                                    seekValue = elapsed
                                    isSeeking = true
                                } else {
                                    controller.seek(to: seekValue)
                                    isSeeking = false
                                }
                            }
                        )
                        .controlSize(.mini)
                        .tint(.white.opacity(0.75))
                        .accessibilityLabel("Позиция воспроизведения")
                        .accessibilityValue(formatTime(isSeeking ? seekValue : elapsed))

                        HStack {
                            Text(formatTime(isSeeking ? seekValue : elapsed))
                            Spacer()
                            Text(formatTime(snapshot.duration))
                        }
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                    }
                }

                HStack(spacing: 17) {
                    playerButton("backward.fill", help: "Предыдущий трек") {
                        controller.previous()
                    }
                    playerButton(
                        snapshot.isPlaying ? "pause.fill" : "play.fill",
                        size: 34,
                        prominent: true,
                        help: snapshot.isPlaying ? "Пауза" : "Продолжить"
                    ) {
                        controller.togglePlayback()
                    }
                    playerButton("forward.fill", help: "Следующий трек") {
                        controller.next()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func historyArtwork(_ entry: PlaybackHistoryEntry, size: CGFloat = 34) -> some View {
        if let data = entry.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        } else {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(.white.opacity(0.07))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    @ViewBuilder
    private func artwork(_ snapshot: NowPlayingSnapshot) -> some View {
        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 126, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.07))
                .frame(width: 126, height: 126)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(.white.opacity(0.38))
                }
        }
    }

    private func playerButton(
        _ symbol: String,
        size: CGFloat = 28,
        prominent: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 13 : 11, weight: .semibold))
                .frame(width: size, height: size)
                .background(
                    prominent ? .white.opacity(0.9) : .white.opacity(0.07),
                    in: Circle()
                )
                .foregroundStyle(prominent ? .black : .white.opacity(0.74))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func playerStatus(symbol: String, title: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct EmptyFeatureView: View {
    let tab: VidgetTab
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab.symbol)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(.white.opacity(0.76))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Text("Функция будет подключена на следующем этапе")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.34))
        }
    }
}

private struct ShelfView: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        if store.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.76))
                Text("Перетащите файлы в панель")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Text("Оригиналы останутся на своих местах")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.34))
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(store.items) { item in
                        ShelfCard(
                            item: item,
                            selected: store.selection.contains(item.id),
                            select: {
                                store.toggleSelection(
                                    item,
                                    extending: NSEvent.modifierFlags.contains(.command)
                                )
                            },
                            remove: { store.remove(item) }
                        )
                        .draggable(item.url) {
                            FileDragPreview(item: item)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    let selected: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    FileIcon(path: item.path)
                        .frame(width: 34, height: 34)
                    Spacer(minLength: 10)
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.32))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать \(item.name) с полки")
                }

                Spacer(minLength: 0)

                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.exists ? .white.opacity(0.85) : .red.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(width: 118, height: 108)
            .background(
                selected ? .white.opacity(0.14) : .white.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? .white.opacity(0.38) : .white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(item.path)
        .accessibilityLabel(item.name)
        .accessibilityValue(selected ? "Выбрано" : "")
        .accessibilityHint(item.exists ? "Выбрать файл на полке" : "Файл недоступен")
    }
}

private struct FileIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .scaledToFit()
    }
}

private struct FileDragPreview: View {
    let item: ShelfItem

    var body: some View {
        HStack(spacing: 8) {
            FileIcon(path: item.path)
                .frame(width: 28, height: 28)
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(9)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        if store.entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.76))
                Text("Скопированный текст появится здесь")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Text("Храним до 40 записей локально")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.34))
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(store.entries) { entry in
                        let hidden = settings.isHidden(
                            .clipboard,
                            id: entry.id.uuidString
                        )
                        Button {
                            if hidden {
                                settings.revealTemporarily(
                                    .clipboard,
                                    id: entry.id.uuidString
                                )
                            } else {
                                store.copy(entry)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(hidden ? "Содержимое скрыто" : entry.text)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(hidden ? 0.42 : 0.82))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Image(systemName: hidden ? "eye" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.32))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Удалить") { store.remove(entry) }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct SnippetView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var settings: SettingsStore
    @State private var showingForm = false
    @State private var label = ""
    @State private var text = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case label
        case text
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.errorMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(1)
                    Spacer()
                    Button("Повторить") { store.reload() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.orange.opacity(0.9))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            if showingForm {
                HStack(spacing: 7) {
                    TextField("Название", text: $label)
                        .textFieldStyle(VidgetTextFieldStyle())
                        .frame(width: 112)
                        .focused($focusedField, equals: .label)
                        .onSubmit { focusedField = .text }

                    TextField("Текст заготовки", text: $text)
                        .textFieldStyle(VidgetTextFieldStyle())
                        .focused($focusedField, equals: .text)
                        .onSubmit(addSnippet)

                    Button(action: addSnippet) {
                        Image(systemName: "checkmark")
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(text.isEmpty ? 0.05 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        showingForm = false
                        label = ""
                        text = ""
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.38))
                    .accessibilityLabel("Закрыть форму")
                }
                .frame(height: 30)
            } else {
                HStack {
                    Text(store.snippets.isEmpty ? "Постоянный список частых фраз" : "Нажмите, чтобы скопировать")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.36))
                    Spacer()
                    Button {
                        showingForm = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(80))
                            focusedField = .label
                        }
                    } label: {
                        Label("Добавить", systemImage: "plus")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 30)
            }

            if store.snippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.64))
                    Text("Добавьте почту, телефон или адрес")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.snippets) { snippet in
                            let hidden = settings.isHidden(
                                .snippets,
                                id: snippet.id.uuidString
                            )
                            Button {
                                if hidden {
                                    settings.revealTemporarily(
                                        .snippets,
                                        id: snippet.id.uuidString
                                    )
                                } else {
                                    store.copy(snippet)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if hidden {
                                            Label("Заготовка скрыта", systemImage: "eye")
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.42))
                                        } else if let label = snippet.label, !label.isEmpty {
                                            Text(label)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.46))
                                        }
                                        if !hidden {
                                            Text(snippet.text)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(.white.opacity(0.84))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Button {
                                        store.remove(snippet)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.28))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Удалить заготовку")
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.top, 8)
    }

    private func addSnippet() {
        guard store.add(label: label, text: text) else { return }
        label = ""
        self.text = ""
        showingForm = false
        focusedField = nil
    }
}

private struct VidgetTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 11.5))
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct NotesView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: SettingsStore
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack {
                    Text("ЧЕРНОВИКИ")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                    Button {
                        store.createNote()
                        editorFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.56))
                    .accessibilityLabel("Создать заметку")
                }
                .padding(.horizontal, 3)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.notes) { note in
                            let hidden = settings.isHidden(
                                .notes,
                                id: note.id.uuidString
                            )
                            Button {
                                store.select(note)
                                if hidden {
                                    settings.revealTemporarily(
                                        .notes,
                                        id: note.id.uuidString
                                    )
                                } else {
                                    editorFocused = true
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hidden ? "Заметка скрыта" : note.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(hidden ? 0.4 : 0.76))
                                        .lineLimit(1)
                                    if hidden {
                                        Image(systemName: "eye")
                                            .font(.system(size: 8.5))
                                            .foregroundStyle(.white.opacity(0.28))
                                    } else {
                                        Text(note.modifiedAt, style: .time)
                                            .font(.system(size: 8.5))
                                            .foregroundStyle(.white.opacity(0.28))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    store.selectedID == note.id ? .white.opacity(0.11) : .white.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: 108)

            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    Button(action: store.copySelected) {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Скопировать заметку")
                    .accessibilityLabel("Скопировать заметку")
                    .disabled(selectedIsHidden)
                    Button(action: store.deleteSelected) {
                        Image(systemName: "trash")
                    }
                    .help("Удалить заметку")
                    .accessibilityLabel("Удалить заметку")
                }
                .font(.system(size: 10.5, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.42))
                .frame(height: 15)

                if selectedIsHidden, let note = store.selectedNote {
                    Button {
                        settings.revealTemporarily(.notes, id: note.id.uuidString)
                        editorFocused = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "eye")
                                .font(.system(size: 20, weight: .light))
                            Text("Заметка скрыта")
                                .font(.system(size: 11.5, weight: .medium))
                            Text("Нажмите, чтобы временно показать")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.52))
                } else {
                    TextEditor(text: selectedText)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .focused($editorFocused)
                        .onExitCommand {
                            editorFocused = false
                            NSApp.keyWindow?.resignKey()
                        }
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            store.ensureDraft()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                editorFocused = true
            }
        }
    }

    private var selectedText: Binding<String> {
        Binding(
            get: { store.selectedNote?.text ?? "" },
            set: { store.updateSelectedText($0) }
        )
    }

    private var selectedIsHidden: Bool {
        guard let note = store.selectedNote else { return false }
        return settings.isHidden(.notes, id: note.id.uuidString)
    }
}

private struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            switch store.access {
            case .notDetermined:
                calendarPermissionView
            case .denied:
                calendarDeniedView
            case .granted:
                calendarEntriesView
            }
        }
        .padding(.top, 8)
    }

    private var calendarPermissionView: some View {
        VStack(spacing: 9) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.white.opacity(0.72))
            Text("Показывать ближайшие встречи?")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text("TopNest читает календарь только на этом Mac.\nРазрешение можно отозвать в Системных настройках.")
                .font(.system(size: 10.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
            Button {
                Task { await store.requestAccess() }
            } label: {
                HStack(spacing: 7) {
                    if store.isRequestingAccess {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(store.isRequestingAccess ? "Ожидание…" : "Разрешить доступ")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 29)
                .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isRequestingAccess)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarDeniedView: some View {
        VStack(spacing: 9) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.orange.opacity(0.8))
            Text("Доступ к календарю выключен")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text("Разрешите полный доступ для TopNest в настройках конфиденциальности.")
                .font(.system(size: 10.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
            Button("Открыть настройки") {
                store.openCalendarPrivacySettings()
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 29)
            .background(.white.opacity(0.11), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var calendarEntriesView: some View {
        if store.entries.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(.green.opacity(0.72))
                Text("На ближайшие семь дней встреч нет")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Button("Обновить") { store.reload() }
                    .font(.system(size: 10.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                            let hidden = settings.isHidden(.calendar, id: entry.id)
                            CalendarEntryRow(
                                entry: entry,
                                now: context.date,
                                prominent: index == 0,
                                hidden: hidden,
                                reveal: {
                                    settings.revealTemporarily(.calendar, id: entry.id)
                                },
                                join: { store.join(entry) }
                            )
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct CalendarEntryRow: View {
    let entry: CalendarEntry
    let now: Date
    let prominent: Bool
    let hidden: Bool
    let reveal: () -> Void
    let join: () -> Void

    var body: some View {
        Group {
            if hidden {
                Button(action: reveal) {
                    HStack(spacing: 9) {
                        Image(systemName: "eye")
                        Text("Встреча скрыта")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Показать")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .foregroundStyle(.white.opacity(0.44))
                }
                .buttonStyle(.plain)
            } else {
                eventContent
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, prominent ? 9 : 7)
        .background(
            prominent ? .white.opacity(0.09) : .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(alignment: .leading) {
            if prominent {
                Capsule()
                    .fill(.blue.opacity(0.7))
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
        }
    }

    private var eventContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(entry.title)
                        .font(.system(size: prominent ? 12 : 11, weight: prominent ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    if prominent {
                        Text(relativeLabel)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(entry.isHappeningNow ? .green.opacity(0.86) : .white.opacity(0.46))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(dateLabel)
                    Text("•")
                    Text(entry.calendarName)
                        .lineLimit(1)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.34))
            }

            Spacer(minLength: 8)

            if entry.meetingURL != nil {
                Button(action: join) {
                    Label("Войти", systemImage: "video.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(.blue.opacity(0.34), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateLabel: String {
        if entry.isAllDay {
            return entry.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return entry.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var relativeLabel: String {
        if entry.startDate <= now, entry.endDate > now {
            return "сейчас"
        }
        let seconds = max(0, entry.startDate.timeIntervalSince(now))
        if seconds < 3_600 {
            return "через \(max(1, Int(seconds / 60))) мин"
        }
        if seconds < 86_400 {
            return "через \(Int(seconds / 3_600)) ч"
        }
        return "через \(Int(seconds / 86_400)) дн"
    }
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Режим приватности", systemImage: "eye.slash.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $store.privacyModeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                Text("Скрывает содержимое во время показа экрана")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.34))

                Divider().overlay(.white.opacity(0.06))

                compactToggle("Буфер обмена", isOn: $store.hidesClipboard)
                compactToggle("Заготовки", isOn: $store.hidesSnippets)
                compactToggle("Календарь", isOn: $store.hidesCalendar)
                compactToggle("Заметки", isOn: $store.hidesNotes)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                Label("Система", systemImage: "macbook")
                    .font(.system(size: 11.5, weight: .semibold))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Запускать при входе")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("Открывать TopNest вместе с macOS")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.launchesAtLogin },
                            set: { store.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if let error = store.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.82))
                }

                Divider().overlay(.white.opacity(0.06))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сохранять снимки")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(store.capturedImagesDirectoryName)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                            .help(store.capturedImagesDirectoryPath)
                    }
                    Spacer()
                    Toggle("", isOn: $store.savesCapturedImages)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                HStack(spacing: 12) {
                    Button("Выбрать папку") { store.chooseCapturedImagesDirectory() }
                    Button("Открыть") { store.openCapturedImagesDirectory() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.9))

                if let error = store.capturedImagesError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.82))
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 8)
    }

    private func compactToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(store.privacyModeEnabled ? 0.68 : 0.36))
    }
}

private struct TranslationView: View {
    @ObservedObject var model: TranslatorModel
    @ObservedObject var screenCapture: ScreenTextCapture
    @State private var configuration: TranslationSession.Configuration?
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var sourceFocused: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Menu {
                    Button {
                        model.chooseSource(nil)
                    } label: {
                        if model.selectedSource == nil {
                            Label("Определять автоматически", systemImage: "checkmark")
                        } else {
                            Text("Определять автоматически")
                        }
                    }
                    Divider()
                    ForEach(SupportedTranslationLanguage.allCases) { language in
                        Button {
                            model.chooseSource(language)
                        } label: {
                            if model.selectedSource == language {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    LanguageMenuLabel(text: model.sourceHeader)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Исходный язык: \(model.sourceHeader)")

                Spacer()
                Button {
                    screenCapture.begin { recognizedText in
                        model.chooseSource(nil)
                        model.sourceText = recognizedText
                    }
                } label: {
                    Image(systemName: screenCapture.isBusy ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(screenCapture.isBusy ? .blue.opacity(0.9) : .white.opacity(0.4))
                        .frame(width: 26, height: 20)
                        .background(.white.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(screenCapture.isBusy)
                .help("Выделить область экрана и распознать текст")
                .accessibilityLabel("Выделить область экрана и распознать текст")
                Spacer()

                Menu {
                    ForEach(SupportedTranslationLanguage.allCases) { language in
                        Button {
                            model.chooseTarget(language)
                        } label: {
                            if model.selectedTarget == language {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    LanguageMenuLabel(text: model.selectedTarget.displayName)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Язык перевода: \(model.selectedTarget.displayName)")
            }
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.34))
            .padding(.horizontal, 9)

            HStack(spacing: 9) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.sourceText)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .focused($sourceFocused)
                        .accessibilityLabel("Исходный текст")
                        .onExitCommand {
                            sourceFocused = false
                            NSApp.keyWindow?.resignKey()
                        }

                    if model.sourceText.isEmpty {
                        Text("Введите текст…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(.white.opacity(sourceFocused ? 0.16 : 0.06), lineWidth: 1)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(.white.opacity(0.04))

                    resultContent
                        .padding(10)

                    if !model.translatedText.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: model.copyResult) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(width: 25, height: 25)
                                        .background(.black.opacity(0.32), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Скопировать перевод")
                                .accessibilityLabel("Скопировать перевод")
                            }
                        }
                        .padding(7)
                    }
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            sourceFocused = true
            scheduleTranslation(for: model.sourceText)
        }
        .onDisappear {
            requestTask?.cancel()
        }
        .onChange(of: model.sourceText) { _, newValue in
            scheduleTranslation(for: newValue)
        }
        .onChange(of: model.selectedSource) { _, _ in
            scheduleTranslation(for: model.sourceText)
        }
        .onChange(of: model.selectedTarget) { _, _ in
            scheduleTranslation(for: model.sourceText)
        }
        .translationTask(configuration) { session in
            let source = await MainActor.run { model.sourceText }
            let pair = await MainActor.run { model.activePair }
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let shouldContinue = await MainActor.run {
                model.beginLanguagePreparation(sourceText: source, pair: pair)
            }
            guard shouldContinue else { return }
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                let shouldTranslate = await MainActor.run {
                    model.beginTranslation(sourceText: source, pair: pair)
                }
                guard shouldTranslate else { return }
                let response = try await session.translate(source)
                await MainActor.run {
                    model.applyTranslation(response.targetText, sourceText: source, pair: pair)
                }
            } catch is CancellationError {
                await MainActor.run {
                    model.applyCancellation(sourceText: source, pair: pair)
                }
            } catch {
                await MainActor.run {
                    model.applyError(error, sourceText: source, pair: pair)
                }
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch screenCapture.state {
        case .recognizing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Распознаём текст…")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.48))
        case .permissionDenied:
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .foregroundStyle(.orange.opacity(0.78))
                Text("Нужен доступ к записи экрана")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Разрешите TopNest доступ и перезапустите приложение.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
                Button("Открыть настройки") {
                    screenCapture.openScreenRecordingSettings()
                }
                .font(.system(size: 9.5, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.blue.opacity(0.9))
            }
        case .noTextFound:
            CaptureStatusView(
                symbol: "text.magnifyingglass",
                message: "В выделенной области текст не найден",
                retry: startScreenCapture
            )
        case .failed(let message):
            CaptureStatusView(
                symbol: "exclamationmark.triangle",
                message: message,
                retry: startScreenCapture
            )
        case .idle, .requestingPermission, .selecting:
            translationResultContent
        }
    }

    @ViewBuilder
    private var translationResultContent: some View {
        switch model.availability {
        case .idle:
            Text("Перевод появится здесь")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.26))
        case .checking:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Проверяем языки…")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.42))
        case .preparing:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Подготавливаем языки…")
                }
                Text("Если пакет ещё не установлен, macOS предложит скачать его один раз.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.52))
        case .ready:
            if model.isTranslating {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Переводим…")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.42))
            } else {
                ScrollView {
                    Text(model.translatedText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.84))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 20)
                }
                .scrollIndicators(.hidden)
            }
        case .unsupported:
            StatusMessage(
                symbol: "character.book.closed.fill",
                text: "Эта языковая пара не поддерживается"
            )
        case .failed(let message):
            StatusMessage(symbol: "exclamationmark.triangle", text: message)
        }
    }

    private func startScreenCapture() {
        screenCapture.begin { recognizedText in
            model.chooseSource(nil)
            model.sourceText = recognizedText
        }
    }

    private func scheduleTranslation(for text: String) {
        requestTask?.cancel()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            configuration = nil
            model.resetOutput()
            return
        }

        requestTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let pair = await model.prepare(text: cleanText),
                  !Task.isCancelled else { return }

            let next = TranslationSession.Configuration(
                source: pair.source.localeLanguage,
                target: pair.target.localeLanguage
            )
            if var current = configuration,
               current.source == next.source,
               current.target == next.target {
                current.invalidate()
                configuration = current
            } else {
                configuration = next
            }
        }
    }
}

private struct CaptureStatusView: View {
    let symbol: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.orange.opacity(0.76))
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Button("Выделить ещё раз", action: retry)
                .font(.system(size: 9.5, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.blue.opacity(0.9))
        }
    }
}

private struct LanguageMenuLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .font(.system(size: 8.5, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(.white.opacity(0.44))
    }
}

private struct StatusMessage: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.orange.opacity(0.76))
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
    }
}
