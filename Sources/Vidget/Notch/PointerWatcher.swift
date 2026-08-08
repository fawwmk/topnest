import AppKit

@MainActor
final class PointerWatcher {
    var onExpansionChange: ((Bool) -> Void)?
    var onInteractionChange: ((Bool) -> Void)?
    var onScreenChange: ((NSScreen) -> Void)?

    private var globalMovementMonitor: Any?
    private var localMovementMonitor: Any?
    private var closeTask: Task<Void, Never>?
    private var geometry: NotchGeometry?
    private var isExpanded = false
    private var isInteractive = false
    private var isExpansionLocked = false

    func start(initialScreen: NSScreen) {
        geometry = NotchGeometry(screen: initialScreen)
        installMovementMonitor()
        evaluatePointer()
    }

    func stop() {
        cancelScheduledClose()
        if let globalMovementMonitor {
            NSEvent.removeMonitor(globalMovementMonitor)
            self.globalMovementMonitor = nil
        }
        if let localMovementMonitor {
            NSEvent.removeMonitor(localMovementMonitor)
            self.localMovementMonitor = nil
        }
    }

    func suspend() {
        isExpansionLocked = false
        setExpanded(false)
        setInteractive(false)
        stop()
    }

    func setExpanded(_ expanded: Bool) {
        if !expanded, isExpansionLocked { return }
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        cancelScheduledClose()
        onExpansionChange?(expanded)
    }

    func setExpansionLocked(_ locked: Bool) {
        guard isExpansionLocked != locked else { return }
        isExpansionLocked = locked
        cancelScheduledClose()
        if locked {
            setExpanded(true)
            setInteractive(true)
        } else {
            evaluatePointer()
        }
    }

    private func installMovementMonitor() {
        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        globalMovementMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
        }
        localMovementMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
            return event
        }
    }

    private func evaluatePointer(closeImmediately: Bool = false) {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) })
                ?? NSScreen.main else { return }

        let nextGeometry = NotchGeometry(screen: screen)
        if geometry?.screenFrame != nextGeometry.screenFrame {
            geometry = nextGeometry
            onScreenChange?(screen)
        } else if geometry == nil {
            geometry = nextGeometry
        }

        guard let geometry else { return }
        let isInside = isExpanded
            ? geometry.expandedInteractionRect.contains(location)
            : geometry.collapsedTriggerRect.contains(location)

        if !isExpanded, isInside {
            setExpanded(true)
            setInteractive(true)
            return
        }

        if isExpanded, isInside {
            cancelScheduledClose()
            setInteractive(true)
            return
        }

        setInteractive(false)
        guard isExpanded else { return }
        guard !isExpansionLocked else { return }

        if closeImmediately {
            setExpanded(false)
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            self.closeTask = nil
            self.evaluatePointer(closeImmediately: true)
        }
    }

    private func cancelScheduledClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func setInteractive(_ interactive: Bool) {
        guard isInteractive != interactive else { return }
        isInteractive = interactive
        onInteractionChange?(interactive)
    }
}
