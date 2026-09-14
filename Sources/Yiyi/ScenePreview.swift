import AppKit

/// Renders the result panel over a real reading window with a real text selection,
/// composed as one padded image for the website. Every pixel comes from live AppKit views.
enum SceneInvocation { case keyboard(String), trackpadHold }

@MainActor func renderScenePreview(panel: ResultPanelController, invocation: SceneInvocation = .keyboard("⌘ ⇧ T"), to url: URL) throws {
    let scale: CGFloat = 2
    let sceneSize = NSSize(width: 900, height: 380)
    let padding: CGFloat = 56

    let reader = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sceneSize.width, height: sceneSize.height),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    reader.title = "Design Notes"
    reader.titlebarAppearsTransparent = true
    reader.appearance = NSAppearance(named: .aqua)
    reader.backgroundColor = .white
    reader.isReleasedWhenClosed = false
    let article = NSTextView(frame: NSRect(x: 64, y: 20, width: 400, height: 300))
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
                                       y: reader.frame.minY + selectionInWindow.maxY - panelWindow.frame.height + 24))
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

    let panelRectPreview = NSRect(origin: NSPoint(x: readerRect.minX + (panelWindow.frame.minX - reader.frame.minX),
                                                  y: readerRect.minY + (panelWindow.frame.minY - reader.frame.minY)), size: panelImage.size)
    switch invocation {
    case let .keyboard(label):
        let cap = NSAttributedString(string: label, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 0.35, alpha: 1)])
        let capSize = cap.size()
        let capRect = NSRect(x: panelRectPreview.minX, y: panelRectPreview.minY - 46, width: capSize.width + 28, height: 30)
        let capPath = NSBezierPath(roundedRect: capRect, xRadius: 8, yRadius: 8)
        NSColor(white: 0.97, alpha: 1).setFill(); capPath.fill()
        NSColor(white: 0, alpha: 0.1).setStroke(); capPath.stroke()
        cap.draw(at: NSPoint(x: capRect.minX + 14, y: capRect.midY - capSize.height / 2))
    case .trackpadHold:
        drawTrackpadSketch(at: NSPoint(x: panelRectPreview.minX + 8, y: panelRectPreview.minY - 84), in: context)
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

/// A restrained line drawing: trackpad, one fingertip pressing, rings showing the hold.
@MainActor private func drawTrackpadSketch(at origin: NSPoint, in context: CGContext) {
    let ink = NSColor(white: 0.3, alpha: 1)
    let padRect = NSRect(x: origin.x, y: origin.y, width: 96, height: 64)
    let pad = NSBezierPath(roundedRect: padRect, xRadius: 9, yRadius: 9)
    NSColor(white: 0.975, alpha: 1).setFill(); pad.fill()
    ink.withAlphaComponent(0.4).setStroke(); pad.lineWidth = 1.5; pad.stroke()

    let touch = NSPoint(x: padRect.midX - 6, y: padRect.midY + 4)
    for (radius, alpha) in [(11.0, 0.5), (18.0, 0.2)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: touch.x - radius, y: touch.y - radius, width: radius * 2, height: radius * 2))
        ink.withAlphaComponent(alpha).setStroke(); ring.lineWidth = 1.5; ring.stroke()
    }

    // Fingertip: rounded pad with a short shaft toward the lower right, staying inside the pad.
    let finger = NSBezierPath()
    finger.move(to: NSPoint(x: touch.x - 6, y: touch.y + 1))
    finger.curve(to: NSPoint(x: touch.x + 6, y: touch.y - 2),
                 controlPoint1: NSPoint(x: touch.x - 6, y: touch.y + 9), controlPoint2: NSPoint(x: touch.x + 7, y: touch.y + 6))
    finger.curve(to: NSPoint(x: touch.x + 30, y: touch.y - 24),
                 controlPoint1: NSPoint(x: touch.x + 14, y: touch.y - 9), controlPoint2: NSPoint(x: touch.x + 24, y: touch.y - 17))
    finger.line(to: NSPoint(x: touch.x + 21, y: touch.y - 31))
    finger.curve(to: NSPoint(x: touch.x - 6, y: touch.y + 1),
                 controlPoint1: NSPoint(x: touch.x + 8, y: touch.y - 18), controlPoint2: NSPoint(x: touch.x - 5, y: touch.y - 9))
    finger.close()
    NSColor.white.setFill(); finger.fill()
    ink.withAlphaComponent(0.8).setStroke(); finger.lineWidth = 1.5; finger.lineJoinStyle = .round; finger.stroke()

    let label = NSAttributedString(string: "⌥ hold", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.8)])
    label.draw(at: NSPoint(x: padRect.maxX + 12, y: padRect.midY - label.size().height / 2))
}

/// Frames an existing settings capture in the same padded scene treatment, cropped to the prompt
/// so the slide stays the same height as the reading scenes.
@MainActor func renderSettingsScene(from source: URL, to url: URL) throws {
    guard let image = NSImage(contentsOf: source), let rep = image.representations.first else {
        throw NSError(domain: "ScenePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read settings capture"])
    }
    let pixel = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    let points = NSSize(width: pixel.width / 2, height: pixel.height / 2)
    let sceneSize = NSSize(width: 900, height: 380)
    let padding: CGFloat = 56
    let scale: CGFloat = 2
    let canvasSize = NSSize(width: sceneSize.width + padding * 2, height: sceneSize.height + padding * 2)
    // Fit the whole window into the scene height so nothing is cut mid-control.
    let fit = min(1, (sceneSize.height - 16) / points.height)
    let drawn = NSSize(width: points.width * fit, height: points.height * fit)
    let windowRect = NSRect(x: padding + (sceneSize.width - drawn.width) / 2, y: padding + (sceneSize.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * scale), pixelsHigh: Int(canvasSize.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    out.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(origin: .zero, size: canvasSize))
    let clip = NSRect(x: padding, y: padding, width: sceneSize.width, height: sceneSize.height)
    _ = clip
    let path = NSBezierPath(roundedRect: windowRect, xRadius: 10, yRadius: 10)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: NSColor(white: 0, alpha: 0.22).cgColor)
    NSColor.white.setFill(); path.fill()
    context.restoreGState()
    context.saveGState(); path.addClip()
    image.draw(in: windowRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()
    NSColor(white: 0, alpha: 0.12).setStroke(); path.lineWidth = 1; path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = out.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScenePreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: url)
}
