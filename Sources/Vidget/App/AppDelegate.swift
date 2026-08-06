import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchController()
        notchController = controller
        controller.start()

        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "TopNest"
        )

        let menu = NSMenu()
        let title = NSMenuItem(title: "TopNest", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: "Показать панель",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let snippetsItem = NSMenuItem(
            title: "Показать файл заготовок",
            action: #selector(revealSnippets),
            keyEquivalent: ""
        )
        snippetsItem.target = self
        menu.addItem(snippetsItem)

        let dataItem = NSMenuItem(
            title: "Показать локальные данные",
            action: #selector(revealDataDirectory),
            keyEquivalent: ""
        )
        dataItem.target = self
        menu.addItem(dataItem)

        let launchItem = NSMenuItem(
            title: "Запускать при входе — скоро",
            action: nil,
            keyEquivalent: ""
        )
        launchItem.isEnabled = false
        menu.addItem(launchItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Завершить TopNest",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        notchController?.togglePanel()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func revealSnippets() {
        notchController?.revealSnippetsFile()
    }

    @objc private func revealDataDirectory() {
        notchController?.revealDataDirectory()
    }
}
