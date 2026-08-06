import AppKit

struct NotchGeometry: Equatable {
    static let windowSize = NSSize(width: 700, height: 260)
    static let expandedSize = NSSize(width: 650, height: 238)
    static let fallbackNotchSize = NSSize(width: 180, height: 24)

    let screenFrame: NSRect
    let notchSize: NSSize

    init(screen: NSScreen) {
        screenFrame = screen.frame

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let physicalWidth = max(0, rightArea.minX - leftArea.maxX)
            let physicalHeight = max(screen.safeAreaInsets.top, 24)
            if physicalWidth > 40 {
                notchSize = NSSize(width: physicalWidth, height: physicalHeight)
                return
            }
        }

        notchSize = Self.fallbackNotchSize
    }

    var windowFrame: NSRect {
        NSRect(
            x: screenFrame.midX - Self.windowSize.width / 2,
            y: screenFrame.maxY - Self.windowSize.height,
            width: Self.windowSize.width,
            height: Self.windowSize.height
        )
    }

    var collapsedTriggerRect: NSRect {
        let visibleRect = NSRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        // Небольшой допуск снизу и по бокам делает наведение уверенным,
        // не превращая всю строку меню в активную область.
        return visibleRect.insetBy(dx: -6, dy: -4)
    }

    var expandedInteractionRect: NSRect {
        // Верх экрана не является границей выхода: AppKit считает maxY
        // невходящей точкой NSRect, из-за чего курсор на самом верхнем
        // пикселе мог попеременно закрывать и открывать панель.
        let topSafetyMargin: CGFloat = 64
        return NSRect(
            x: screenFrame.midX - Self.expandedSize.width / 2,
            y: screenFrame.maxY - Self.expandedSize.height,
            width: Self.expandedSize.width,
            height: Self.expandedSize.height + topSafetyMargin
        )
    }
}
