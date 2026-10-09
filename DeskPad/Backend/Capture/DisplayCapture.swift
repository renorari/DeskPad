import CoreMedia
import ScreenCaptureKit

extension Notification.Name {
    static let displayCaptureDidStart = Notification.Name("DisplayCaptureDidStart")
}

/// Captures a display with ScreenCaptureKit and hands over only frames whose content changed.
///
/// Call `start` and `stop` from the main thread. Frames are delivered on a background queue.
final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let displayID: CGDirectDisplayID
    private let onFrame: (CVPixelBuffer) -> Void
    private let sampleQueue = DispatchQueue(label: "DeskPad.DisplayCapture", qos: .userInteractive)
    private var stream: SCStream?
    private var outputSize = CGSize.zero
    private var isWanted = false
    private var isConnecting = false

    init(displayID: CGDirectDisplayID, onFrame: @escaping (CVPixelBuffer) -> Void) {
        self.displayID = displayID
        self.onFrame = onFrame
    }

    /// Starts capturing at the given pixel size, or resizes a running capture.
    func start(outputSize: CGSize) {
        self.outputSize = outputSize
        isWanted = true
        if let stream {
            stream.updateConfiguration(makeConfiguration()) { _ in }
        } else {
            connect()
        }
    }

    func stop() {
        isWanted = false
        stream?.stopCapture { _ in }
        stream = nil
    }

    private func connect() {
        guard isWanted, stream == nil, !isConnecting else {
            return
        }
        // Asking ScreenCaptureKit without permission would show the system prompt on every retry.
        guard CGPreflightScreenCaptureAccess() else {
            retryLater()
            return
        }
        isConnecting = true
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, _ in
            DispatchQueue.main.async {
                self?.didLoad(content)
            }
        }
    }

    private func didLoad(_ content: SCShareableContent?) {
        isConnecting = false
        guard isWanted, stream == nil else {
            return
        }
        // Missing until Screen Recording is allowed, or briefly after the virtual display appears.
        guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
            retryLater()
            return
        }

        let stream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: makeConfiguration(),
            delegate: self
        )
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            retryLater()
            return
        }
        self.stream = stream
        stream.startCapture { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    NotificationCenter.default.post(name: .displayCaptureDidStart, object: self)
                } else {
                    self?.streamDidFail(stream)
                }
            }
        }
    }

    private func streamDidFail(_ failedStream: SCStream) {
        guard stream === failedStream else {
            return
        }
        stream = nil
        retryLater()
    }

    private func retryLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.connect()
        }
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(outputSize.width))
        configuration.height = max(1, Int(outputSize.height))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        return configuration
    }

    // MARK: - SCStreamOutput

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard
            type == .screen,
            sampleBuffer.isValid,
            Self.frameStatus(of: sampleBuffer) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }
        onFrame(pixelBuffer)
    }

    /// `.complete` means new content; idle repeats of an unchanged screen are skipped.
    private static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int
        else {
            return nil
        }
        return SCFrameStatus(rawValue: rawStatus)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError _: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.streamDidFail(stream)
        }
    }
}
