import AppKit

@MainActor
final class PointerWatcher {
    var onExpansionChange: ((Bool) -> Void)?
    var onInteractionChange: ((Bool) -> Void)?
    var onScreenChange: ((NSScreen) -> Void)?

    private var timer: Timer?
    private var movementMonitor: Any?
    private var geometry: NotchGeometry?
    private var isExpanded = false
    private var isInteractive = false
    private var isExpansionLocked = false
    private var closeDeadline: Date?

    func start(initialScreen: NSScreen) {
        geometry = NotchGeometry(screen: initialScreen)
        installMovementMonitor()
        installTimer(interval: 0.25)
        evaluatePointer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let movementMonitor {
            NSEvent.removeMonitor(movementMonitor)
            self.movementMonitor = nil
        }
    }

    func setExpanded(_ expanded: Bool) {
        if !expanded, isExpansionLocked { return }
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        closeDeadline = nil
        installTimer(interval: expanded ? 1.0 / 60.0 : 0.25)
        onExpansionChange?(expanded)
    }

    func setExpansionLocked(_ locked: Bool) {
        guard isExpansionLocked != locked else { return }
        isExpansionLocked = locked
        closeDeadline = nil
        if locked {
            setExpanded(true)
            setInteractive(true)
        } else {
            evaluatePointer()
        }
    }

    private func installMovementMonitor() {
        movementMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
        }
    }

    private func installTimer(interval: TimeInterval) {
        timer?.invalidate()
        let nextTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
        }
        nextTimer.tolerance = interval * 0.2
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    private func evaluatePointer() {
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
            closeDeadline = nil
            setInteractive(true)
            return
        }

        setInteractive(false)
        guard isExpanded else { return }
        guard !isExpansionLocked else { return }

        if let deadline = closeDeadline {
            if Date() >= deadline {
                setExpanded(false)
            }
        } else {
            closeDeadline = Date().addingTimeInterval(0.18)
        }
    }

    private func setInteractive(_ interactive: Bool) {
        guard isInteractive != interactive else { return }
        isInteractive = interactive
        onInteractionChange?(interactive)
    }
}
