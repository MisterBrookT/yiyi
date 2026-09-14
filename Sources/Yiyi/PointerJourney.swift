import AppKit
import YiyiCore

/// Posts only to this disposable test window. Never reads or changes the clipboard.
@MainActor func runPointerJourney() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 560, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "yiyi — pointer integration check"
    window.isReleasedWhenClosed = false
    let editor = NSTextView(frame: NSRect(x: 20, y: 20, width: 520, height: 120))
    editor.string = "A deliberate gesture keeps the original selection."
    editor.font = .systemFont(ofSize: 18)
    window.contentView?.addSubview(editor)
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor); app.activate(ignoringOtherApps: true)
    let monitor = PointerGestureMonitor()
    var captures: [String?] = []
    monitor.onTrigger = { _, text in captures.append(text) }
    monitor.configure(config: PointerTriggerConfig(enabled: true), commandCount: 1)
    defer { monitor.stop(); window.close() }
    guard monitor.isEnabled else { throw pointerFailure(monitor.status) }
    try await Task.sleep(for: .milliseconds(350))
    let screenPoint = window.convertPoint(toScreen: editor.convert(NSPoint(x: 150, y: 70), to: nil))
    let position = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
    func post(_ type: CGEventType, option: Bool, xOffset: CGFloat = 0) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: position.x + xOffset, y: position.y), mouseButton: .left)!
        event.flags = option ? .maskAlternate : []
        event.post(tap: .cghidEventTap)
    }
    var firedBeforeRelease = false
    func gesture(option: Bool, duration: Int, drag: Bool = false) async throws {
        window.makeFirstResponder(editor); editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        try await Task.sleep(for: .milliseconds(80))
        let before = captures.count
        post(.leftMouseDown, option: option)
        if drag { try await Task.sleep(for: .milliseconds(120)); post(.leftMouseDragged, option: option, xOffset: 20) }
        try await Task.sleep(for: .milliseconds(duration))
        firedBeforeRelease = captures.count > before
        post(.leftMouseUp, option: option, xOffset: drag ? 20 : 0)
        try await Task.sleep(for: .milliseconds(150))
    }
    defer { post(.leftMouseUp, option: false) }
    try await gesture(option: false, duration: 500)
    guard captures.isEmpty else { throw pointerFailure("Ordinary click triggered a command") }
    try await gesture(option: true, duration: 100)
    guard captures.isEmpty else { throw pointerFailure("Short click triggered a command") }
    try await gesture(option: true, duration: 500, drag: true)
    guard captures.isEmpty else { throw pointerFailure("Dragging triggered a command") }
    try await gesture(option: true, duration: 700)
    guard captures.count == 1 else { throw pointerFailure("Expected exactly one real event-tap dispatch; got \(captures.count)") }
    guard firedBeforeRelease else { throw pointerFailure("Command did not start while the button was still held") }
    guard captures[0] == editor.string else { throw pointerFailure("Selection at press time was not preserved") }
    print("PASS: real pointer event tap; ordinary/short/drag ignored; fires once while still held, release inert; original selection preserved")
}
private func pointerFailure(_ message: String) -> NSError { NSError(domain: "PointerJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
