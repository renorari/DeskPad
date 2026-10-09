import Cocoa
import ReSwift

enum AppDelegateAction: Action {
    case didFinishLaunching
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var permissionGuide: PermissionGuideWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        window = makeWindow()
        NSApplication.shared.mainMenu = makeMainMenu()
        window.makeKeyAndOrderFront(nil)

        store.dispatch(AppDelegateAction.didFinishLaunching)

        showPermissionGuideIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }

    private func makeWindow() -> NSWindow {
        let viewController = ScreenViewController()
        let window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.title = "DeskPad"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = CGSize(width: 5120, height: 2160)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        return window
    }

    private func showPermissionGuideIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else {
            return
        }
        let permissionGuide = PermissionGuideWindowController()
        permissionGuide.showWindow(nil)
        self.permissionGuide = permissionGuide
    }

    private func makeMainMenu() -> NSMenu {
        let subMenu = NSMenu(title: "MainMenu")
        subMenu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        ))
        let mainMenuItem = NSMenuItem()
        mainMenuItem.submenu = subMenu
        let mainMenu = NSMenu()
        mainMenu.items = [mainMenuItem]
        return mainMenu
    }
}
