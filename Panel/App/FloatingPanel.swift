import AppKit

enum OverlayWindowLevel {
    static let interactivePanel = NSWindow.Level.mainMenu + 3
}

final class FloatingPanel: NSPanel {
    convenience init(frame: NSRect) {
        self.init(
            contentRect: frame,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isFloatingPanel = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false

        animationBehavior = .none
        level = OverlayWindowLevel.interactivePanel
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        acceptsMouseMovedEvents = true
        canBecomeVisibleWithoutLogin = true
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

//    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool {
//        true
//    }
}
