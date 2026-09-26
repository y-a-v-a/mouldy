import AppKit
import MouldCore
import MouldRender
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let options: LaunchOptions
    private var controller: MouldController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var sessionMonitor: SessionMonitor?
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let renderer: MouldRenderer
        do {
            renderer = try MouldRenderer()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Mould can't grow here"
            alert.informativeText = "Metal is unavailable: \(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        controller = MouldController(renderer: renderer, options: options)
        controller.onStateChange = { [weak self] in self?.refreshMenu() }

        hotKey = HotKey(combo: .clearMould) { [weak self] in self?.controller.wipeOff() }
        if hotKey == nil {
            log.error("could not register \(KeyCombo.clearMould.displayString, privacy: .public); use the menu bar item to wipe")
        }
        sessionMonitor = SessionMonitor { [weak self] trigger in
            log.notice("\(trigger.rawValue, privacy: .public), starting over")
            self?.controller.reset()
        }

        setUpStatusItem()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        sessionMonitor?.stop()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image(progress: 0)
        statusItem.button?.toolTip = "Mould"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        detailLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(detailLine)
        menu.addItem(.separator())

        let wipe = NSMenuItem(title: "Wipe It Off", action: #selector(wipeOff), keyEquivalent: "m")
        wipe.keyEquivalentModifierMask = [.control, .option, .command]
        wipe.target = self
        menu.addItem(wipe)
        menu.addItem(.separator())

        menu.addItem(submenu("Fruit", items: Theme.allCases.map { theme in
            item(theme.displayName, #selector(pickTheme(_:)), tag: Int(theme.rawValue))
        }))
        menu.addItem(submenu("Thickness", items: [
            item("Faint (for the squeamish)", #selector(pickOpacity(_:)), tag: 55),
            item("Hearty", #selector(pickOpacity(_:)), tag: 80),
            item("Fully furry", #selector(pickOpacity(_:)), tag: 92),
        ]))
        menu.addItem(submenu("Growth Speed", items: [
            item("One hour (sensible)", #selector(pickSpeed(_:)), tag: 1),
            item("Ten minutes", #selector(pickSpeed(_:)), tag: 6),
            item("One minute (demo)", #selector(pickSpeed(_:)), tag: 60),
        ]))

        let away = item("Pause While I'm Away", #selector(togglePauseWhenAway), tag: 0)
        away.identifier = NSUserInterfaceItemIdentifier("away")
        menu.addItem(away)
        let screenshots = item("Hide During Screenshots", #selector(toggleHideDuringScreenshots), tag: 0)
        screenshots.identifier = NSUserInterfaceItemIdentifier("screenshots")
        screenshots.toolTip = "Lets ⌘⇧4 pick single windows instead of the mould-covered screen."
        menu.addItem(screenshots)
        let login = item("Open at Login", #selector(toggleLoginItem), tag: 0)
        login.identifier = NSUserInterfaceItemIdentifier("login")
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("About Mould", #selector(showAbout), tag: 0))
        let quit = NSMenuItem(title: "Quit Mould", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenu()

        // Keep the icon's little spores in step with the screen.
        let iconTimer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        RunLoop.main.add(iconTimer, forMode: .common)
    }

    private func item(_ title: String, _ action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshIcon() {
        statusItem.button?.image = StatusIcon.image(progress: controller.progress)
    }

    private func refreshMenu() {
        guard let controller, let menu = statusItem?.menu else { return }
        refreshIcon()
        let percent = Int((controller.progress * 100).rounded())
        statusLine.title = MouldMood.headline(progress: controller.progress)
        let minutes = Int(controller.minutesAtScreen.rounded(.down))
        var detail = "\(percent)% grown · \(minutes) min at the screen"
        if controller.isAway { detail += " · paused, you're away" }
        detailLine.title = detail

        for top in menu.items {
            switch top.identifier?.rawValue {
            case "away": top.state = controller.pausesWhenAway ? .on : .off
            case "screenshots": top.state = controller.hidesDuringScreenshots ? .on : .off
            case "login": top.state = SMAppService.mainApp.status == .enabled ? .on : .off
            default: break
            }
            guard let sub = top.submenu else { continue }
            for option in sub.items {
                switch option.action {
                case #selector(pickTheme(_:)): option.state = option.tag == Int(controller.theme.rawValue) ? .on : .off
                case #selector(pickOpacity(_:)): option.state = option.tag == Int((controller.opacity * 100).rounded()) ? .on : .off
                case #selector(pickSpeed(_:)): option.state = Double(option.tag) == controller.speed ? .on : .off
                default: break
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func wipeOff() { controller.wipeOff() }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        controller.theme = Theme(rawValue: UInt32(sender.tag)) ?? .orange
        refreshMenu()
    }

    @objc private func pickOpacity(_ sender: NSMenuItem) {
        controller.opacity = Double(sender.tag) / 100
        refreshMenu()
    }

    @objc private func pickSpeed(_ sender: NSMenuItem) {
        controller.speed = Double(sender.tag)
        refreshMenu()
    }

    @objc private func togglePauseWhenAway() {
        controller.pausesWhenAway.toggle()
        refreshMenu()
    }

    @objc private func toggleHideDuringScreenshots() {
        controller.hidesDuringScreenshots.toggle()
        refreshMenu()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("login item change failed: \(error, privacy: .public)")
        }
        refreshMenu()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "A slowly growing reminder that you've been staring at this screen for too long.\n\n"
                    + "Press \(KeyCombo.clearMould.displayString) to wipe it off. Locking the screen or starting the screensaver resets it too.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }
}
