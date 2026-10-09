import AppKit

/// Builds the menu bar. Settings items act on the given screen controller.
enum MainMenu {
    static func make(screenController: ScreenViewController) -> NSMenu {
        let windowMenu = makeWindowMenu(screenController: screenController)
        NSApp.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        for submenu in [makeAppMenu(), makeDisplayMenu(screenController: screenController), windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: "DeskPad")
        menu.addItem(
            title: String(localized: "About DeskPad"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        )
        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Hide DeskPad"), action: #selector(NSApplication.hide(_:)), key: "h")
        menu.addItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        )
        menu.addItem(
            title: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:))
        )
        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Quit DeskPad"), action: #selector(NSApplication.terminate(_:)), key: "q")
        return menu
    }

    private static func makeDisplayMenu(screenController: ScreenViewController) -> NSMenu {
        let menu = NSMenu(title: String(localized: "Display"))

        let resolutionMenu = NSMenu(title: String(localized: "Resolution"))
        // Filled in each time it opens, since the available modes depend on the display.
        resolutionMenu.delegate = screenController
        menu.addItem(withTitle: resolutionMenu.title, action: nil, keyEquivalent: "").submenu = resolutionMenu

        menu.addItem(
            title: String(localized: "Rotate"),
            action: #selector(ScreenViewController.rotateDisplay(_:)),
            key: "r",
            target: screenController
        )
        menu.addItem(.separator())

        let frameRateMenu = NSMenu(title: String(localized: "Frame Rate"))
        for frameRate in Preferences.frameRates {
            frameRateMenu.addItem(
                title: String(localized: "\(frameRate) fps"),
                action: #selector(ScreenViewController.selectFrameRate(_:)),
                target: screenController
            ).tag = frameRate
        }
        menu.addItem(withTitle: frameRateMenu.title, action: nil, keyEquivalent: "").submenu = frameRateMenu

        menu.addItem(
            title: String(localized: "Show Cursor"),
            action: #selector(ScreenViewController.toggleShowsCursor(_:)),
            target: screenController
        )
        return menu
    }

    private static func makeWindowMenu(screenController: ScreenViewController) -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(title: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        menu.addItem(title: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Keep on Top"),
            action: #selector(ScreenViewController.toggleKeepsWindowOnTop(_:)),
            key: "t",
            modifiers: [.command, .option],
            target: screenController
        )
        menu.addItem(
            title: String(localized: "Bring to Front When Cursor Enters"),
            action: #selector(ScreenViewController.toggleBringsWindowToFront(_:)),
            target: screenController
        )
        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
