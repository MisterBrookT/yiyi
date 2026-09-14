import AppKit

/// Renders the result panel over a real reading window with a real text selection,
/// composed as one padded image for the website. Every pixel comes from live AppKit views.
@MainActor func renderScenePreview(panel: ResultPanelController, to url: URL) throws {
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
    let article = NSTextView(frame: NSRect(x: 64, y: 24, width: 400, height: 320))
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
                                       y: reader.frame.minY + selectionInWindow.maxY - panelWindow.frame.height + 4))
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
    // A quiet keycap showing how the panel was invoked.
    let cap = NSAttributedString(string: "⌥ hold", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 0.35, alpha: 1)])
    let capSize = cap.size()
    let capRect = NSRect(x: panelRectPreview.minX, y: panelRectPreview.minY - 46, width: capSize.width + 28, height: 30)
    let capPath = NSBezierPath(roundedRect: capRect, xRadius: 8, yRadius: 8)
    NSColor(white: 0.97, alpha: 1).setFill(); capPath.fill()
    NSColor(white: 0, alpha: 0.1).setStroke(); capPath.stroke()
    cap.draw(at: NSPoint(x: capRect.minX + 14, y: capRect.midY - capSize.height / 2))

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
