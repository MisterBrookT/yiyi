import AppKit

/// Accessory apps still need an Edit menu for first-responder keyboard commands.
@MainActor func installEditingMenu(settingsTarget: NSObject? = nil) {
    let main = NSMenu()
    let application = NSMenuItem()
    let appMenu = NSMenu(title: "yiyi")
    if let settingsTarget {
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = settingsTarget
        appMenu.addItem(.separator())
    }
    let quit = NSMenuItem(title: "Quit yiyi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    appMenu.addItem(quit)
    application.submenu = appMenu
    main.addItem(application)

    let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "Save", action: Selector(("saveSettings:")), keyEquivalent: "s")
    file.submenu = fileMenu; main.addItem(file)

    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Edit")
    menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    edit.submenu = menu
    main.addItem(edit)
    NSApp.mainMenu = main
}
