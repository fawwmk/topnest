import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notchController: NotchController?
    private var statusItem: NSStatusItem?
    private let settingsStore = SettingsStore()
    private weak var launchAtLoginItem: NSMenuItem?

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
            title: "Запускать при входе",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchAtLoginItem = launchItem
        updateLaunchAtLoginItem()
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
        menu.delegate = self
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        settingsStore.refreshLaunchAtLoginStatus()
        updateLaunchAtLoginItem()
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

    @objc private func toggleLaunchAtLogin() {
        settingsStore.refreshLaunchAtLoginStatus()
        settingsStore.setLaunchAtLogin(!settingsStore.launchesAtLogin)
        updateLaunchAtLoginItem()
    }

    private func updateLaunchAtLoginItem() {
        launchAtLoginItem?.state = settingsStore.launchesAtLogin ? .on : .off
    }
}
