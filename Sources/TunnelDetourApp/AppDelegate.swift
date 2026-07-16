import AppKit
import TunnelDetourCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let controller = MainWindowController()
        windowController = controller

        Task.detached(priority: .utility) {
            try? GoogleIPRanges.refreshCache()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            if let iconURL = Bundle.main.url(
                forResource: "TunnelDetourMenuBar@2x",
                withExtension: "png"
            ), let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
                button.imagePosition = .imageOnly
                button.toolTip = "TunnelDetour"
            }
            button.target = self
            button.action = #selector(toggleWindow)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        showMainWindow(controller)
    }

    @objc private func toggleWindow() {
        guard let controller = windowController else { return }

        if controller.window?.isVisible == true {
            controller.close()
        } else {
            showMainWindow(controller)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let controller = windowController else { return true }
        showMainWindow(controller)
        return true
    }

    private func showMainWindow(_ controller: MainWindowController) {
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "TunnelDetour")
        appMenu.addItem(
            withTitle: "Quit TunnelDetour",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        addEditItem("Undo", action: Selector(("undo:")), key: "z", modifiers: [.command], to: editMenu)
        addEditItem("Redo", action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        addEditItem("Cut", action: #selector(NSText.cut(_:)), key: "x", modifiers: [.command], to: editMenu)
        addEditItem("Copy", action: #selector(NSText.copy(_:)), key: "c", modifiers: [.command], to: editMenu)
        addEditItem("Paste", action: #selector(NSText.paste(_:)), key: "v", modifiers: [.command], to: editMenu)
        editMenu.addItem(.separator())
        addEditItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a", modifiers: [.command], to: editMenu)

        editMenu.addItem(.separator())
        addEditItem("Cut", action: #selector(NSText.cut(_:)), key: "x", modifiers: [.control], to: editMenu)
        addEditItem("Copy", action: #selector(NSText.copy(_:)), key: "c", modifiers: [.control], to: editMenu)
        addEditItem("Paste", action: #selector(NSText.paste(_:)), key: "v", modifiers: [.control], to: editMenu)
        addEditItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a", modifiers: [.control], to: editMenu)
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func addEditItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        alternate: Bool = false,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.isAlternate = alternate
        menu.addItem(item)
    }
}
