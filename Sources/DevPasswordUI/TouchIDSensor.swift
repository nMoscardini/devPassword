import SwiftUI
import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// Touch ID drawn inside the lock screen, as Apple Passwords does. No floating panel.
/// The glyph is bound to its own LAContext. Once the view is in a window it hands the context
/// to `onReady`, which starts listening for a finger. Each new view (new `.id`) is a fresh attempt.
/// Clicking the glyph calls `onClick` (try again).
struct TouchIDSensor: NSViewRepresentable {
    let onReady: (LAContext) -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> SensorHost {
        SensorHost(onReady: onReady, onClick: onClick)
    }

    func updateNSView(_ view: SensorHost, context: Context) {
        view.onClick = onClick
    }

    final class SensorHost: NSView {
        let laContext = LAContext()
        private let onReady: (LAContext) -> Void
        var onClick: () -> Void
        private var started = false

        init(onReady: @escaping (LAContext) -> Void, onClick: @escaping () -> Void) {
            self.onReady = onReady
            self.onClick = onClick
            super.init(frame: .zero)
            let glyph = LAAuthenticationView(context: laContext, controlSize: .regular)
            glyph.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glyph)
            // Pin the glyph to all four edges. Centred with no size it had zero size, drew nothing,
            // and macOS fell back to the floating panel (15 October).
            NSLayoutConstraint.activate([
                glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
                glyph.trailingAnchor.constraint(equalTo: trailingAnchor),
                glyph.topAnchor.constraint(equalTo: topAnchor),
                glyph.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !started else { return }
            started = true
            // Evaluate only once the glyph is in a window and laid out. Before that, macOS falls back to the floating panel.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { self?.started = false; return }
                self.layoutSubtreeIfNeeded()
                self.onReady(self.laContext)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
        override func mouseUp(with event: NSEvent) { onClick() }
    }
}
