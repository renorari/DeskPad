import Foundation
import ReSwift

enum ScreenConfigurationAction: Action {
    case set(resolution: CGSize, scaleFactor: CGFloat)
}

func screenConfigurationSideEffect() -> SideEffect {
    var isObserving = false

    return { _, dispatch, getState in
        guard !isObserving else {
            return
        }
        isObserving = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: .main
        ) { _ in
            guard let screen = NSScreen.screens.first(where: {
                $0.displayID == getState()?.screenConfigurationState.displayID
            }) else {
                return
            }
            dispatch(ScreenConfigurationAction.set(
                resolution: screen.frame.size,
                scaleFactor: screen.backingScaleFactor
            ))
        }
    }
}
