import Foundation
import ReSwift

enum MouseLocationAction: Action {
    case located(isWithinScreen: Bool)
    case requestMove(toPoint: NSPoint)
}

func mouseLocationSideEffect() -> SideEffect {
    var timer: Timer?

    return { action, dispatch, getState in
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                let mouseLocation = NSEvent.mouseLocation
                let screenContainingMouse = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
                let isWithinScreen = screenContainingMouse?.displayID == getState()?.screenConfigurationState.displayID
                dispatch(MouseLocationAction.located(isWithinScreen: isWithinScreen))
            }
            // Lets macOS coalesce the wakeups with other timers.
            timer?.tolerance = 0.1
        }

        guard
            case let MouseLocationAction.requestMove(point) = action,
            let displayID = getState()?.screenConfigurationState.displayID
        else {
            return
        }
        CGDisplayMoveCursorToPoint(displayID, point)
    }
}
