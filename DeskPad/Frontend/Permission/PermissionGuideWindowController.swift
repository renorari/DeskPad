import Cocoa

/// A floating panel that lets the user drag DeskPad straight into
/// System Settings → Privacy & Security → Screen Recording.
final class PermissionGuideWindowController: NSWindowController {
    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    convenience init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Screen Recording Permission")
        // Stay visible above System Settings while the user drags the icon over.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        panel.contentView = makeContentView()
        panel.center()
    }

    private func makeContentView() -> NSView {
        let titleLabel = NSTextField(labelWithString: String(localized: "Allow DeskPad to record the screen"))
        titleLabel.font = .boldSystemFont(ofSize: 15)

        let stepsLabel = NSTextField(wrappingLabelWithString: String(localized: """
        1. Open System Settings.
        2. Drag the DeskPad icon below into the Screen Recording list.
        3. Reopen DeskPad.

        If DeskPad is already listed, turn it off and on again.
        """))
        stepsLabel.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let iconView = AppIconDragView()
        let iconCaption = NSTextField(labelWithString: String(localized: "Drag me"))
        iconCaption.textColor = .secondaryLabelColor
        iconCaption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let openSettingsButton = NSButton(
            title: String(localized: "Open System Settings"),
            target: self,
            action: #selector(openSystemSettings)
        )
        openSettingsButton.keyEquivalent = "\r"
        let reopenButton = NSButton(title: String(localized: "Reopen DeskPad"), target: self, action: #selector(reopenApp))
        let buttons = NSStackView(views: [reopenButton, openSettingsButton])

        let stack = NSStackView(views: [titleLabel, stepsLabel, iconView, iconCaption, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])
        return contentView
    }

    @objc private func openSystemSettings() {
        NSWorkspace.shared.open(Self.screenRecordingSettingsURL)
    }

    /// Screen Recording permission only takes effect after a relaunch.
    @objc private func reopenApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// Shows the app icon and drags the app bundle when pulled out of the panel.
private final class AppIconDragView: NSImageView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL

    init() {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: appURL.path)
        imageScaling = .scaleProportionallyUpOrDown
        toolTip = String(localized: "Drag into the Screen Recording list")
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            heightAnchor.constraint(equalToConstant: 96),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with _: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .outsideApplication ? .copy : []
    }
}
