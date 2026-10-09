import Cocoa
import ReSwift

enum ScreenViewAction: Action {
    case setDisplayID(CGDirectDisplayID)
}

class ScreenViewController: SubscriberViewController<ScreenViewData>, NSWindowDelegate {
    private let display = CGVirtualDisplay.makeDeskPadDisplay()
    private let screenView = MetalScreenView()
    private lazy var capture = DisplayCapture(displayID: display.displayID) { [screenView] pixelBuffer in
        screenView.render(pixelBuffer)
    }

    private var pendingCaptureUpdate: DispatchWorkItem?
    private var isWindowHighlighted = false
    private var previousResolution: CGSize?
    private var previousScaleFactor: CGFloat?

    override func loadView() {
        view = screenView
        screenView.onDrawableSizeChange = { [weak self] _ in
            self?.scheduleCaptureUpdate()
        }
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickOnScreen)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        store.dispatch(ScreenViewAction.setDisplayID(display.displayID))
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        applyWindowLevel()
    }

    override func update(with viewData: ScreenViewData) {
        if viewData.isWindowHighlighted != isWindowHighlighted {
            isWindowHighlighted = viewData.isWindowHighlighted
            updateWindowHighlight()
        }

        if
            viewData.resolution != .zero,
            viewData.resolution != previousResolution
            || viewData.scaleFactor != previousScaleFactor
        {
            previousResolution = viewData.resolution
            previousScaleFactor = viewData.scaleFactor
            resizeWindow(to: viewData.resolution)
            // The display itself changed, so reconnect rather than resize the stream.
            capture.stop()
            updateCapture()
        }
    }

    private func updateWindowHighlight() {
        view.window?.backgroundColor = isWindowHighlighted
            ? NSColor(named: "TitleBarActive")
            : NSColor(named: "TitleBarInactive")
        if isWindowHighlighted, Preferences.bringsWindowToFrontOnCursorEnter {
            view.window?.orderFrontRegardless()
        }
    }

    private func applyWindowLevel() {
        view.window?.level = Preferences.keepsWindowOnTop ? .floating : .normal
    }

    private func resizeWindow(to resolution: CGSize) {
        guard let window = view.window else {
            return
        }
        window.setContentSize(resolution)
        window.contentAspectRatio = resolution
        center(window, on: hostScreen(for: window))
    }

    // MARK: - Capture

    /// Live resizing changes the drawable size every frame, so stream updates are batched.
    private func scheduleCaptureUpdate() {
        pendingCaptureUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            self?.updateCapture()
        }
        pendingCaptureUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: update)
    }

    /// Captures only as many pixels as the window shows, and nothing while it is hidden.
    private func updateCapture() {
        guard
            let resolution = previousResolution,
            let scaleFactor = previousScaleFactor,
            let window = view.window,
            window.occlusionState.contains(.visible)
        else {
            capture.stop()
            return
        }
        let drawableSize = screenView.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else {
            return
        }
        capture.start(outputSize: CGSize(
            width: min(drawableSize.width, resolution.width * scaleFactor),
            height: min(drawableSize.height, resolution.height * scaleFactor)
        ))
    }

    func windowDidChangeOcclusionState(_: Notification) {
        updateCapture()
    }

    // MARK: - Keeping the window off the virtual display

    // If the window ends up on the display it is mirroring, it renders itself recursively
    // and becomes unreachable, so it is moved back to a physical screen.

    func windowDidChangeScreen(_ notification: Notification) {
        moveWindowOffVirtualDisplayIfNeeded(notification.object as? NSWindow)
    }

    func windowDidMove(_ notification: Notification) {
        moveWindowOffVirtualDisplayIfNeeded(notification.object as? NSWindow)
    }

    private func moveWindowOffVirtualDisplayIfNeeded(_ window: NSWindow?) {
        guard
            let window,
            window.screen?.displayID == display.displayID,
            // Wait until the user lets go; windowDidMove fires again when the drag ends.
            NSEvent.pressedMouseButtons == 0,
            let screen = hostScreen(for: window)
        else {
            return
        }
        center(window, on: screen)
    }

    /// The screen the window should live on: its current one, unless that is the virtual display.
    private func hostScreen(for window: NSWindow) -> NSScreen? {
        if let screen = window.screen, screen.displayID != display.displayID {
            return screen
        }
        return NSScreen.screens.first { $0.displayID != display.displayID }
    }

    private func center(_ window: NSWindow, on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }
        var frame = window.frame
        if frame.width > visibleFrame.width || frame.height > visibleFrame.height {
            let scale = min(visibleFrame.width / frame.width, visibleFrame.height / frame.height)
            frame.size = NSSize(width: frame.width * scale, height: frame.height * scale)
        }
        frame.origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        let snappingOffset: CGFloat = 30
        let contentSize = window.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard
            let screenResolution = previousResolution,
            abs(contentSize.width - screenResolution.width) < snappingOffset
        else {
            return frameSize
        }
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: screenResolution)).size
    }

    // MARK: - Actions

    @objc private func didClickOnScreen(_ gestureRecognizer: NSGestureRecognizer) {
        guard let screenResolution = previousResolution else {
            return
        }
        let clickedPoint = gestureRecognizer.location(in: view)
        let onScreenPoint = NSPoint(
            x: clickedPoint.x / view.frame.width * screenResolution.width,
            y: (view.frame.height - clickedPoint.y) / view.frame.height * screenResolution.height
        )
        store.dispatch(MouseLocationAction.requestMove(toPoint: onScreenPoint))
    }
}

// MARK: - Menu bar settings

extension ScreenViewController: NSMenuItemValidation, NSMenuDelegate {
    @objc func rotateDisplay(_: NSMenuItem) {
        guard
            let current = DisplayModes.current(for: display.displayID),
            let rotated = DisplayModes.rotated(current, for: display.displayID)
        else {
            return
        }
        DisplayModes.apply(rotated, to: display.displayID)
    }

    @objc func selectResolution(_ sender: NSMenuItem) {
        guard let mode = DisplayModes.available(for: display.displayID).first(where: {
            Int($0.ioDisplayModeID) == sender.tag
        }) else {
            return
        }
        DisplayModes.apply(mode, to: display.displayID)
    }

    @objc func selectFrameRate(_ sender: NSMenuItem) {
        Preferences.frameRate = sender.tag
        capture.reloadConfiguration()
    }

    @objc func toggleShowsCursor(_: NSMenuItem) {
        Preferences.showsCursor.toggle()
        capture.reloadConfiguration()
    }

    @objc func toggleKeepsWindowOnTop(_: NSMenuItem) {
        Preferences.keepsWindowOnTop.toggle()
        applyWindowLevel()
    }

    @objc func toggleBringsWindowToFront(_: NSMenuItem) {
        Preferences.bringsWindowToFrontOnCursorEnter.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(rotateDisplay(_:)):
            guard let current = DisplayModes.current(for: display.displayID) else {
                return false
            }
            return DisplayModes.rotated(current, for: display.displayID) != nil
        case #selector(selectFrameRate(_:)):
            menuItem.state = menuItem.tag == Preferences.frameRate ? .on : .off
        case #selector(toggleShowsCursor(_:)):
            menuItem.state = Preferences.showsCursor ? .on : .off
        case #selector(toggleKeepsWindowOnTop(_:)):
            menuItem.state = Preferences.keepsWindowOnTop ? .on : .off
        case #selector(toggleBringsWindowToFront(_:)):
            menuItem.state = Preferences.bringsWindowToFrontOnCursorEnter ? .on : .off
        default:
            break
        }
        return true
    }

    /// Fills the Resolution menu: landscape modes first, then portrait ones.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = DisplayModes.current(for: display.displayID)
        let modes = DisplayModes.available(for: display.displayID)
        guard !modes.isEmpty else {
            menu.addItem(withTitle: String(localized: "No Resolutions Available"), action: nil, keyEquivalent: "")
            return
        }
        for group in [modes.filter { !$0.isPortrait }, modes.filter(\.isPortrait)] where !group.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            for mode in group {
                let item = menu.addItem(withTitle: mode.title, action: #selector(selectResolution(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(mode.ioDisplayModeID)
                item.state = mode.title == current?.title ? .on : .off
            }
        }
    }
}

private extension CGVirtualDisplay {
    static func makeDeskPadDisplay() -> CGVirtualDisplay {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "DeskPad Display"
        descriptor.maxPixelsWide = 7680
        descriptor.maxPixelsHigh = 4320
        descriptor.sizeInMillimeters = CGSize(width: 1600, height: 1000)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // Modes at twice a size also offer that size in HiDPI.
        settings.modes = [
            // 32:9
            CGVirtualDisplayMode(width: 5120, height: 1440, refreshRate: 60),
            // 21:9 (239:100, 12:5)
            CGVirtualDisplayMode(width: 5120, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 6880, height: 2880, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 3440, height: 1440, refreshRate: 60),
            // 16:9
            CGVirtualDisplayMode(width: 5120, height: 2880, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 2560, height: 1440, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60),
            CGVirtualDisplayMode(width: 1600, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1366, height: 768, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 720, refreshRate: 60),
            // 16:10
            CGVirtualDisplayMode(width: 5120, height: 3200, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 2400, refreshRate: 60),
            CGVirtualDisplayMode(width: 3360, height: 2100, refreshRate: 60),
            CGVirtualDisplayMode(width: 2880, height: 1800, refreshRate: 60),
            CGVirtualDisplayMode(width: 2560, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1200, refreshRate: 60),
            CGVirtualDisplayMode(width: 1680, height: 1050, refreshRate: 60),
            CGVirtualDisplayMode(width: 1440, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 800, refreshRate: 60),
            // Portrait 9:16
            CGVirtualDisplayMode(width: 2160, height: 3840, refreshRate: 60),
            CGVirtualDisplayMode(width: 1440, height: 2560, refreshRate: 60),
            CGVirtualDisplayMode(width: 1080, height: 1920, refreshRate: 60),
            // Portrait 10:16
            CGVirtualDisplayMode(width: 2400, height: 3840, refreshRate: 60),
            CGVirtualDisplayMode(width: 1600, height: 2560, refreshRate: 60),
            CGVirtualDisplayMode(width: 1200, height: 1920, refreshRate: 60),
        ]
        display.apply(settings)
        return display
    }
}
