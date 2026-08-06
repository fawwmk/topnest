import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchController {
    private let viewModel = NotchViewModel()
    private let pointerWatcher = PointerWatcher()
    private var panel: NotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let geometry = NotchGeometry(screen: screen)
        let panel = NotchPanel(frame: geometry.windowFrame)
        panel.contentView = NSHostingView(rootView: NotchRootView(viewModel: viewModel))
        panel.orderFrontRegardless()
        self.panel = panel

        pointerWatcher.onExpansionChange = { [weak self] expanded in
            self?.viewModel.setExpanded(expanded)
            self?.updateKeyboardFocus()
        }
        pointerWatcher.onInteractionChange = { [weak panel] interactive in
            panel?.ignoresMouseEvents = !interactive
        }
        pointerWatcher.onScreenChange = { [weak self] screen in
            self?.movePanel(to: screen)
        }
        pointerWatcher.start(initialScreen: screen)

        viewModel.$selectedTab
            .dropFirst()
            .sink { [weak self] tab in
                self?.updateKeyboardFocus(for: tab)
            }
            .store(in: &cancellables)

        viewModel.translator.$isPreparingLanguages
            .removeDuplicates()
            .sink { [weak self] isPreparing in
                self?.pointerWatcher.setExpansionLocked(isPreparing)
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
                self?.movePanel(to: screen)
            }
        }
    }

    func stop() {
        pointerWatcher.stop()
        viewModel.mediaController.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panel?.close()
    }

    func togglePanel() {
        let expanded = !viewModel.isExpanded
        pointerWatcher.setExpanded(expanded)
        panel?.ignoresMouseEvents = !expanded
        if expanded {
            panel?.orderFrontRegardless()
        }
        updateKeyboardFocus()
    }

    func revealSnippetsFile() {
        viewModel.snippetStore.revealFile()
    }

    func revealDataDirectory() {
        guard let url = try? AppStorage.supportDirectory() else { return }
        NSWorkspace.shared.open(url)
    }

    private func movePanel(to screen: NSScreen) {
        panel?.setFrame(NotchGeometry(screen: screen).windowFrame, display: true)
        panel?.orderFrontRegardless()
    }

    private func updateKeyboardFocus(for tab: VidgetTab? = nil) {
        guard let panel else { return }
        let activeTab = tab ?? viewModel.selectedTab
        let acceptsInput = viewModel.isExpanded && activeTab.acceptsKeyboardInput
        panel.acceptsKeyboardInput = acceptsInput
        if acceptsInput {
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }
}
