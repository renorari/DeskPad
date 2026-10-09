import Cocoa
import ReSwift

enum AppDelegateAction: Action {
    case didFinishLaunching
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var permissionGuide: PermissionGuideWindowController?
    private var captureStartObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_: Notification) {
        let screenController = ScreenViewController()
        window = makeWindow(screenController: screenController)
        NSApplication.shared.mainMenu = MainMenu.make(screenController: screenController)
        window.makeKeyAndOrderFront(nil)

        store.dispatch(AppDelegateAction.didFinishLaunching)

        showPermissionGuideIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }

    private func makeWindow(screenController: ScreenViewController) -> NSWindow {
        let window = NSWindow(contentViewController: screenController)
        window.delegate = screenController
        window.title = "DeskPad"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = CGSize(width: 7680, height: 4320)
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

        // Capture starts on its own once permission is granted, so the guide is no longer needed.
        captureStartObserver = NotificationCenter.default.addObserver(
            forName: .displayCaptureDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closePermissionGuide()
        }
    }

    private func closePermissionGuide() {
        permissionGuide?.close()
        permissionGuide = nil
        if let captureStartObserver {
            NotificationCenter.default.removeObserver(captureStartObserver)
        }
        captureStartObserver = nil
    }
}
