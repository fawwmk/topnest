import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import Vision

enum ScreenTextCaptureState: Equatable {
    case idle
    case requestingPermission
    case selecting
    case recognizing
    case permissionDenied
    case noTextFound
    case failed(String)
}

enum ScreenTextCaptureError: LocalizedError {
    case displayNotFound
    case selectionTooSmall
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Не удалось найти выбранный экран"
        case .selectionTooSmall: "Выделенная область слишком мала"
        case .noTextFound: "В выделенной области текст не найден"
        }
    }
}

@MainActor
final class ScreenTextCapture: ObservableObject {
    @Published private(set) var state: ScreenTextCaptureState = .idle

    private var overlayPanels: [ScreenSelectionPanel] = []
    private var recognizedTextHandler: ((String) -> Void)?

    var isBusy: Bool {
        switch state {
        case .requestingPermission, .selecting, .recognizing: true
        default: false
        }
    }

    func begin(onRecognizedText: @escaping (String) -> Void) {
        guard !isBusy else { return }
        recognizedTextHandler = onRecognizedText
        showSelectionOverlay()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissStatus() {
        if !isBusy {
            state = .idle
        }
    }

    private func showSelectionOverlay() {
        closeOverlays()
        state = .selecting

        overlayPanels = NSScreen.screens.map { screen in
            let panel = ScreenSelectionPanel(screen: screen)
            panel.selectionView.onCancel = { [weak self] in
                self?.cancelSelection()
            }
            panel.selectionView.onSelection = { [weak self, weak screen] rect in
                guard let self, let screen else { return }
                self.finishSelection(rect, on: screen)
            }
            panel.orderFrontRegardless()
            return panel
        }

        let pointer = NSEvent.mouseLocation
        let activePanel = overlayPanels.first(where: { $0.frame.contains(pointer) })
            ?? overlayPanels.first
        activePanel?.makeKey()
        if let activePanel {
            activePanel.makeFirstResponder(activePanel.selectionView)
        }
    }

    private func cancelSelection() {
        closeOverlays()
        state = .idle
        recognizedTextHandler = nil
    }

    private func finishSelection(_ screenRect: CGRect, on screen: NSScreen) {
        guard screenRect.width >= 8, screenRect.height >= 8 else {
            state = .failed(ScreenTextCaptureError.selectionTooSmall.localizedDescription)
            closeOverlays()
            return
        }

        closeOverlays()
        state = .recognizing

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Даём WindowServer один кадр, чтобы overlay успел исчезнуть из снимка.
            try? await Task.sleep(for: .milliseconds(90))
            do {
                let image = try await Self.capture(rect: screenRect, on: screen)
                let text = try await Self.recognizeText(in: image)
                guard !text.isEmpty else { throw ScreenTextCaptureError.noTextFound }
                recognizedTextHandler?(text)
                recognizedTextHandler = nil
                state = .idle
            } catch ScreenTextCaptureError.noTextFound {
                state = .noTextFound
            } catch {
                if !CGPreflightScreenCaptureAccess() {
                    state = .permissionDenied
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func closeOverlays() {
        overlayPanels.forEach { $0.orderOut(nil) }
        overlayPanels.removeAll()
    }

    private static func capture(rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let screenNumber = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
        guard let screenNumber,
              let display = content.displays.first(where: { $0.displayID == screenNumber }) else {
            throw ScreenTextCaptureError.displayNotFound
        }

        let localRect = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = max(1, Int(localRect.width * scale))
        configuration.height = max(1, Int(localRect.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    nonisolated private static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["ru-RU", "en-US", "it-IT"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let observations = (request.results ?? []).sorted { lhs, rhs in
                let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if verticalDistance > 0.025 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

@MainActor
private final class ScreenSelectionPanel: NSPanel {
    let selectionView: ScreenSelectionView

    init(screen: NSScreen) {
        selectionView = ScreenSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ScreenSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let window, selectionRect.width >= 1, selectionRect.height >= 1 else {
            onCancel?()
            return
        }
        onSelection?(window.convertToScreen(selectionRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        let selection = selectionRect
        if selection.width > 0, selection.height > 0 {
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.copy)
                context.setFillColor(NSColor.clear.cgColor)
                context.fill(selection)
                context.restoreGState()
            }

            let border = NSBezierPath(roundedRect: selection, xRadius: 3, yRadius: 3)
            border.lineWidth = 2
            NSColor.systemBlue.setStroke()
            border.stroke()

            let dimensions = "\(Int(selection.width)) × \(Int(selection.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = dimensions.size(withAttributes: attributes)
            let labelRect = NSRect(
                x: selection.midX - size.width / 2 - 7,
                y: max(selection.minY - 25, 8),
                width: size.width + 14,
                height: 20
            )
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
            dimensions.draw(
                at: NSPoint(x: labelRect.minX + 7, y: labelRect.minY + 3),
                withAttributes: attributes
            )
        } else {
            let instruction = "Выделите область с текстом  ·  Esc — отмена"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = instruction.size(withAttributes: attributes)
            instruction.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY + 28),
                withAttributes: attributes
            )
        }
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).intersection(bounds)
    }
}
