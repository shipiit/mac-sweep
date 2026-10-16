import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NotchState {
    var isExpanded = false
    /// Physical notch size; zero-width on Macs/screens without one.
    var notchSize = CGSize(width: 200, height: 32)
    var hasNotch = false

    static let earWidth: CGFloat = 66
    static let expandedSize = CGSize(width: 740, height: 300)

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width + Self.earWidth * 2, height: notchSize.height)
    }
}

/// Owns a borderless, non-activating panel parked over the notch. The panel is always sized for the
/// expanded state but ignores the mouse while collapsed, so it never blocks the menu bar beneath it.
@MainActor
final class NotchController {
    private let state = NotchState()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    private func show() {
        guard panel == nil, let screen = NSScreen.builtIn ?? NSScreen.main else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: NotchView(state: state).environment(app).appAccent())
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        position(on: screen)
        panel.orderFrontRegardless()

        let handler: (NSEvent) -> Void = { [weak self] _ in self?.trackMouse() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in handler(event); return event }) {
            monitors.append(local)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = NSScreen.builtIn ?? NSScreen.main else { return }
                self.position(on: screen)
            }
        }
    }

    private func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        state.isExpanded = false
    }

    private func position(on screen: NSScreen) {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            state.hasNotch = true
            state.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: max(screen.safeAreaInsets.top, menuBarHeight))
        } else {
            state.hasNotch = false
            state.notchSize = CGSize(width: 0, height: max(menuBarHeight, 24))
        }
        let size = NotchState.expandedSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        panel?.setFrame(frame, display: true)
    }

    private func trackMouse() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let target = state.isExpanded ? NotchState.expandedSize : state.collapsedSize
        let active = NSRect(x: frame.midX - target.width / 2, y: frame.maxY - target.height, width: target.width, height: target.height)
            .insetBy(dx: state.isExpanded ? -8 : 0, dy: state.isExpanded ? -8 : 0)
        let inside = active.contains(mouse)
        guard inside != state.isExpanded else { return }
        panel.ignoresMouseEvents = !inside
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { state.isExpanded = inside }
    }
}

extension NSScreen {
    /// The screen with a camera housing, if any; that's where the notch HUD belongs.
    static var builtIn: NSScreen? {
        screens.first { $0.auxiliaryTopLeftArea != nil }
    }
}
