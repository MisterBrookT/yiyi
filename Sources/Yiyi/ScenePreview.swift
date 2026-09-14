import AppKit

/// Renders the result panel over a real reading window with a real text selection,
/// composed as one padded image for the website. Every pixel comes from live AppKit views.
enum SceneInvocation { case keyboard(String), trackpadHold }

@MainActor func renderScenePreview(panel: ResultPanelController, invocation: SceneInvocation = .keyboard("⌘ ⇧ T"), to url: URL) throws {
    let scale: CGFloat = 2
    let sceneSize = NSSize(width: 900, height: 400)
    let padding: CGFloat = 56

    let reader = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sceneSize.width, height: sceneSize.height),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    reader.title = "Design Notes"
    reader.titlebarAppearsTransparent = true
    reader.appearance = NSAppearance(named: .aqua)
    reader.backgroundColor = .white
    reader.isReleasedWhenClosed = false
    let article = NSTextView(frame: NSRect(x: 64, y: 30, width: 400, height: 310))
    article.isEditable = false; article.drawsBackground = false
    article.textContainerInset = .zero; article.textContainer?.lineFragmentPadding = 0
    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 12
    let body = NSMutableAttributedString()
    body.append(NSAttributedString(string: "On quiet interfaces\n", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]))
    let selection = "Design is intelligence made visible. A quiet interface lets content lead."
    let prose = "\(selection) The best tools disappear while you use them: they show up when needed, do one thing well, and step back the moment the work continues.\n\nThat restraint is not an absence of design. It is the result of many decisions about what to leave out, and of the discipline to keep leaving it out as the product grows."
    body.append(NSAttributedString(string: prose, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(white: 0.22, alpha: 1), .paragraphStyle: paragraph]))
    article.textStorage?.setAttributedString(body)
    reader.contentView?.addSubview(article)
    let selectedRange = (body.string as NSString).range(of: selection)
    article.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(srgbRed: 0.72, green: 0.83, blue: 1.0, alpha: 1), forCharacterRange: selectedRange)
    reader.setFrameOrigin(NSPoint(x: 200, y: 200))
    reader.orderFront(nil)
    reader.contentView?.layoutSubtreeIfNeeded()

    panel.showLoading(command: "Translate to Chinese", source: selection)
    panel.showResult("设计是可视化的智慧。\n\n安静的界面让内容成为主角。")
    let panelWindow = panel.window
    // Sit just beneath the selected sentence, the way it appears after a real trigger.
    let glyphRange = article.layoutManager!.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
    let selectionRect = article.layoutManager!.boundingRect(forGlyphRange: glyphRange, in: article.textContainer!)
    let selectionInWindow = article.convert(selectionRect, to: nil)
    panelWindow.setFrameOrigin(NSPoint(x: reader.frame.minX + article.frame.maxX + 28,
                                       y: reader.frame.minY + selectionInWindow.maxY - panelWindow.frame.height + 44))
    panelWindow.orderFront(nil)

    func snapshot(_ window: NSWindow) -> NSImage? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size); image.addRepresentation(rep); return image
    }
    guard let readerImage = snapshot(reader), let panelImage = snapshot(panelWindow) else {
        throw NSError(domain: "ScenePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not snapshot windows"])
    }

    let canvasSize = NSSize(width: sceneSize.width + padding * 2, height: sceneSize.height + padding * 2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * scale), pixelsHigh: Int(canvasSize.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(origin: .zero, size: canvasSize))

    let readerRect = NSRect(x: padding, y: padding, width: sceneSize.width, height: sceneSize.height)
    let readerPath = NSBezierPath(roundedRect: readerRect, xRadius: 12, yRadius: 12)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: NSColor(white: 0, alpha: 0.22).cgColor)
    NSColor.white.setFill(); readerPath.fill()
    context.restoreGState()
    context.saveGState(); readerPath.addClip()
    readerImage.draw(in: readerRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()
    NSColor(white: 0, alpha: 0.12).setStroke(); readerPath.lineWidth = 1; readerPath.stroke()
    for (kind, color) in [(NSWindow.ButtonType.closeButton, trafficRed), (.miniaturizeButton, trafficYellow), (.zoomButton, trafficGreen)] {
        guard let button = reader.standardWindowButton(kind), let superview = button.superview else { continue }
        let inWindow = superview.convert(button.frame, to: nil)
        drawTrafficLight(center: NSPoint(x: readerRect.minX + inWindow.midX, y: readerRect.minY + inWindow.midY), color: color)
    }

    let panelRectPreview = NSRect(origin: NSPoint(x: readerRect.minX + (panelWindow.frame.minX - reader.frame.minX),
                                                  y: readerRect.minY + (panelWindow.frame.minY - reader.frame.minY)), size: panelImage.size)
    let deckSize = NSSize(width: 236, height: 134)
    let deckOrigin = NSPoint(x: panelRectPreview.minX + 12, y: panelRectPreview.minY - 12 - deckSize.height)
    switch invocation {
    case let .keyboard(label):
        drawInputDeck(at: deckOrigin, size: deckSize, pressedKeys: Set(label.split(separator: " ").map(String.init)), fingerOnTrackpad: false)
    case .trackpadHold:
        drawInputDeck(at: deckOrigin, size: deckSize, pressedKeys: [], fingerOnTrackpad: true)
    }

    let panelOrigin = NSPoint(x: readerRect.minX + (panelWindow.frame.minX - reader.frame.minX),
                              y: readerRect.minY + (panelWindow.frame.minY - reader.frame.minY))
    let panelRect = NSRect(origin: panelOrigin, size: panelImage.size)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor(white: 0, alpha: 0.24).cgColor)
    NSColor.white.setFill(); NSBezierPath(roundedRect: panelRect, xRadius: 16, yRadius: 16).fill()
    context.restoreGState()
    panelImage.draw(in: panelRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScenePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: url)
    reader.close()
}

let trafficRed = NSColor(srgbRed: 1.0, green: 0.373, blue: 0.341, alpha: 1)
let trafficYellow = NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1)
let trafficGreen = NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)

@MainActor func drawTrafficLight(center: NSPoint, color: NSColor, diameter: CGFloat = 12) {
    let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    let path = NSBezierPath(ovalIn: rect)
    color.setFill(); path.fill()
    color.blended(withFraction: 0.18, of: .black)?.setStroke(); path.lineWidth = 0.5; path.stroke()
}

/// A compact laptop deck: a few keyboard rows on top, the trackpad directly beneath.
/// Keys are schematic; only the keys that matter are labelled. Either some keys are pressed
/// (keyboard shortcut) or a fingertip rests on the trackpad (press-and-hold).
@MainActor private func drawInputDeck(at origin: NSPoint, size: NSSize, pressedKeys: Set<String>, fingerOnTrackpad: Bool) {
    let ink = NSColor(white: 0.3, alpha: 1)
    let accent = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1)
    let body = NSBezierPath(roundedRect: NSRect(origin: origin, size: size), xRadius: 10, yRadius: 10)
    NSColor(white: 0.965, alpha: 1).setFill(); body.fill()
    NSColor(white: 0, alpha: 0.1).setStroke(); body.lineWidth = 1; body.stroke()

    let inset: CGFloat = 8
    let gap: CGFloat = 3
    let keyHeight: CGFloat = 11
    let width = size.width - inset * 2
    // Rows from the top: numbers, QWERTY (with T), ASDF, ZXCV with ⇧ ends, then the modifier row.
    let rows: [[(label: String, units: CGFloat)]] = [
        Array(repeating: (label: "", units: 1), count: 13) + [(label: "⌫", units: 1.6)],
        [(label: "⇥", units: 1.6)] + [("", 1), ("", 1), ("", 1), ("", 1), ("T", 1)].map { (label: $0.0, units: $0.1) } + Array(repeating: (label: "", units: 1), count: 8),
        [(label: "⇪", units: 1.9)] + Array(repeating: (label: "", units: 1), count: 11) + [(label: "⏎", units: 1.7)],
        [(label: "⇧", units: 2.4)] + Array(repeating: (label: "", units: 1), count: 10) + [(label: "⇧", units: 2.2)],
        [(label: "fn", units: 1), (label: "⌃", units: 1), (label: "⌥", units: 1), (label: "⌘", units: 1.3), (label: "", units: 5.3), (label: "⌘", units: 1.3), (label: "⌥", units: 1), (label: "", units: 1), (label: "", units: 1), (label: "", units: 1)]
    ]
    var y = origin.y + size.height - inset - keyHeight
    var highlightedShiftDone = false
    for row in rows {
        let totalUnits = row.reduce(0) { $0 + $1.units }
        let unit = (width - gap * CGFloat(row.count - 1)) / totalUnits
        var x = origin.x + inset
        for key in row {
            let rect = NSRect(x: x, y: y, width: key.units * unit, height: keyHeight)
            var pressed = !key.label.isEmpty && pressedKeys.contains(key.label)
            if pressed && key.label == "⇧" { if highlightedShiftDone { pressed = false } else { highlightedShiftDone = true } }
            if pressed && key.label == "⌘" && x > origin.x + size.width / 2 { pressed = false }
            if pressed && key.label == "⌥" && x > origin.x + size.width / 2 { pressed = false }
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            (pressed ? accent : NSColor.white).setFill(); path.fill()
            (pressed ? accent : NSColor(white: 0, alpha: 0.09)).setStroke(); path.lineWidth = 0.5; path.stroke()
            if !key.label.isEmpty {
                let text = NSAttributedString(string: key.label, attributes: [.font: NSFont.systemFont(ofSize: 6.5, weight: pressed ? .semibold : .regular), .foregroundColor: pressed ? NSColor.white : ink.withAlphaComponent(0.7)])
                let textSize = text.size()
                text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            }
            x += rect.width + gap
        }
        y -= keyHeight + gap
    }

    // Trackpad directly beneath the keyboard, centred.
    let padTop = y + keyHeight - 6
    let padRect = NSRect(x: origin.x + size.width / 2 - 52, y: origin.y + inset - 1, width: 104, height: padTop - (origin.y + inset - 1))
    let pad = NSBezierPath(roundedRect: padRect, xRadius: 5, yRadius: 5)
    (fingerOnTrackpad ? NSColor(white: 0.93, alpha: 1) : NSColor.white).setFill(); pad.fill()
    NSColor(white: 0, alpha: 0.12).setStroke(); pad.lineWidth = 1; pad.stroke()

    guard fingerOnTrackpad else { return }
    let touch = NSPoint(x: padRect.midX - 6, y: padRect.midY + 3)
    for (radius, alpha) in [(10.0, 0.9), (17.0, 0.4)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: touch.x - radius, y: touch.y - radius, width: radius * 2, height: radius * 2))
        accent.withAlphaComponent(alpha).setStroke(); ring.lineWidth = 1.5; ring.stroke()
    }
    let finger = NSBezierPath()
    finger.move(to: NSPoint(x: touch.x - 6, y: touch.y + 1))
    finger.curve(to: NSPoint(x: touch.x + 6, y: touch.y - 2), controlPoint1: NSPoint(x: touch.x - 6, y: touch.y + 9), controlPoint2: NSPoint(x: touch.x + 7, y: touch.y + 6))
    finger.curve(to: NSPoint(x: touch.x + 34, y: touch.y - 30), controlPoint1: NSPoint(x: touch.x + 14, y: touch.y - 10), controlPoint2: NSPoint(x: touch.x + 26, y: touch.y - 22))
    finger.line(to: NSPoint(x: touch.x + 25, y: touch.y - 37))
    finger.curve(to: NSPoint(x: touch.x - 6, y: touch.y + 1), controlPoint1: NSPoint(x: touch.x + 8, y: touch.y - 20), controlPoint2: NSPoint(x: touch.x - 5, y: touch.y - 9))
    finger.close()
    NSColor.white.setFill(); finger.fill()
    ink.withAlphaComponent(0.85).setStroke(); finger.lineWidth = 1.5; finger.lineJoinStyle = .round; finger.stroke()
}

/// Frames an existing settings capture in the same padded scene treatment. The window is shown
/// near full size, anchored at the top, and fades out at the bottom edge of the scene.
@MainActor func renderSettingsScene(from source: URL, to url: URL) throws {
    guard let image = NSImage(contentsOf: source), let rep = image.representations.first else {
        throw NSError(domain: "ScenePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read settings capture"])
    }
    let points = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
    let sceneSize = NSSize(width: 900, height: 400)
    let padding: CGFloat = 56
    let scale: CGFloat = 2
    let canvasSize = NSSize(width: sceneSize.width + padding * 2, height: sceneSize.height + padding * 2)
    let fit: CGFloat = 0.92
    let drawn = NSSize(width: points.width * fit, height: points.height * fit)
    let windowRect = NSRect(x: padding + (sceneSize.width - drawn.width) / 2, y: padding + sceneSize.height - drawn.height, width: drawn.width, height: drawn.height)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * scale), pixelsHigh: Int(canvasSize.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    out.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(origin: .zero, size: canvasSize))

    // Draw into a transparency layer so the bottom fade applies to window, border and shadow alike.
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    let path = NSBezierPath(roundedRect: windowRect, xRadius: 10, yRadius: 10)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: NSColor(white: 0, alpha: 0.22).cgColor)
    NSColor.white.setFill(); path.fill()
    context.restoreGState()
    context.saveGState(); path.addClip()
    image.draw(in: windowRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()
    NSColor(white: 0, alpha: 0.12).setStroke(); path.lineWidth = 1; path.stroke()
    // The capture comes from an inactive window, so its traffic lights are grey; paint the real colours.
    for (index, color) in [trafficRed, trafficYellow, trafficGreen].enumerated() {
        drawTrafficLight(center: NSPoint(x: windowRect.minX + (15.75 + 23 * CGFloat(index)) * fit, y: windowRect.maxY - 15.75 * fit), color: color, diameter: 12 * fit)
    }
    // Fade the lower edge so the window reads as continuing below the frame.
    context.setBlendMode(.destinationIn)
    let fadeTop = padding + 120
    let gradient = NSGradient(colors: [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: 1)])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: canvasSize.width, height: fadeTop), angle: 90)
    NSColor(white: 0, alpha: 1).setFill(); NSRect(x: 0, y: fadeTop, width: canvasSize.width, height: canvasSize.height - fadeTop).fill()
    context.setBlendMode(.normal)
    context.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = out.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScenePreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: url)
}
