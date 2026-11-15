import SwiftUI
import AppKit

/// SwiftUI's gestures do not see right clicks on macOS, so this transparent AppKit view reports them. It only
/// claims the click when the current event is a right click (or a two-finger trackpad click); left clicks, drags
/// and pinches fall straight through to the scope underneath.
struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: ((CGPoint) -> Void)?

        override var isFlipped: Bool { true } // origin at the top left, like SwiftUI

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            onRightClick?(CGPoint(x: p.x, y: p.y))
        }
    }
}
