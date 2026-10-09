import CoreGraphics

/// Lists and switches display modes through the public CoreGraphics API.
enum DisplayModes {
    /// Distinct modes, largest first.
    static func available(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let modes = (CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]) ?? []
        var seen = Set<String>()
        return modes
            .filter { $0.isUsableForDesktopGUI() && seen.insert($0.title).inserted }
            .sorted { ($0.width * $0.height, $0.isHiDPI ? 1 : 0) > ($1.width * $1.height, $1.isHiDPI ? 1 : 0) }
    }

    static func current(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        return CGDisplayCopyDisplayMode(displayID)
    }

    static func apply(_ mode: CGDisplayMode, to displayID: CGDirectDisplayID) {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success else {
            return
        }
        guard CGConfigureDisplayWithDisplayMode(configuration, displayID, mode, nil) == .success else {
            CGCancelDisplayConfiguration(configuration)
            return
        }
        CGCompleteDisplayConfiguration(configuration, .permanently)
    }

    /// The same mode turned on its side (landscape ↔ portrait), if the display offers one.
    static func rotated(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        return available(for: displayID).first {
            $0.width == mode.height && $0.height == mode.width && $0.isHiDPI == mode.isHiDPI
        }
    }
}

extension CGDisplayMode {
    var isHiDPI: Bool {
        return pixelWidth > width
    }

    var isPortrait: Bool {
        return height > width
    }

    var title: String {
        return isHiDPI ? "\(width) × \(height) (HiDPI)" : "\(width) × \(height)"
    }
}
