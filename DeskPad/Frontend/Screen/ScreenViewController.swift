import Cocoa
import ReSwift

enum ScreenViewAction: Action {
    case setDisplayID(CGDirectDisplayID)
}

class ScreenViewController: SubscriberViewController<ScreenViewData>, NSWindowDelegate {
    private let display = CGVirtualDisplay.makeDeskPadDisplay()
    private var stream: CGDisplayStream?
    private var isWindowHighlighted = false
    private var previousResolution: CGSize?
    private var previousScaleFactor: CGFloat?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickOnScreen)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        store.dispatch(ScreenViewAction.setDisplayID(display.displayID))
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
            startStream(resolution: viewData.resolution, scaleFactor: viewData.scaleFactor)
        }
    }

    private func updateWindowHighlight() {
        view.window?.backgroundColor = isWindowHighlighted
            ? NSColor(named: "TitleBarActive")
            : NSColor(named: "TitleBarInactive")
        if isWindowHighlighted {
            view.window?.orderFrontRegardless()
        }
    }

    private func resizeWindow(to resolution: CGSize) {
        guard let window = view.window else {
            return
        }
        window.setContentSize(resolution)
        window.contentAspectRatio = resolution
        center(window, on: hostScreen(for: window))
    }

    private func startStream(resolution: CGSize, scaleFactor: CGFloat) {
        stream?.stop()
        stream = CGDisplayStream(
            dispatchQueueDisplay: display.displayID,
            outputWidth: Int(resolution.width * scaleFactor),
            outputHeight: Int(resolution.height * scaleFactor),
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: [
                CGDisplayStream.showCursor: true,
            ] as CFDictionary,
            queue: .main,
            handler: { [weak self] _, _, frameSurface, _ in
                if let surface = frameSurface {
                    self?.view.layer?.contents = surface
                }
            }
        )
        stream?.start()
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

private extension CGVirtualDisplay {
    static func makeDeskPadDisplay() -> CGVirtualDisplay {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "DeskPad Display"
        descriptor.maxPixelsWide = 5120
        descriptor.maxPixelsHigh = 2160
        descriptor.sizeInMillimeters = CGSize(width: 1600, height: 1000)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [
            // 32:9
            CGVirtualDisplayMode(width: 5120, height: 1440, refreshRate: 60),
            // 21:9 (239:100, 12:5)
            CGVirtualDisplayMode(width: 5120, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 3440, height: 1440, refreshRate: 60),
            // 16:9
            CGVirtualDisplayMode(width: 3840, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 2560, height: 1440, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60),
            CGVirtualDisplayMode(width: 1600, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1366, height: 768, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 720, refreshRate: 60),
            // 16:10
            CGVirtualDisplayMode(width: 2560, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1200, refreshRate: 60),
            CGVirtualDisplayMode(width: 1680, height: 1050, refreshRate: 60),
            CGVirtualDisplayMode(width: 1440, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 800, refreshRate: 60),
        ]
        display.apply(settings)
        return display
    }
}
