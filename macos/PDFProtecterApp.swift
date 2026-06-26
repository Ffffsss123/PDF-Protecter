import AppKit

private let windowSize = NSSize(width: 980, height: 760)
private let sidebarWidth: CGFloat = 250
private let cardHeight: CGFloat = 520
private let L = Localizer()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var root: NSView!
    private var sidebar: NSView!
    private var content: NSView!
    private var currentMode = Mode.create
    private var navButtons: [Mode: NSButton] = [:]
    private var navTitleLabels: [Mode: NSTextField] = [:]
    private var navSubtitleLabels: [Mode: NSTextField] = [:]
    private var fields: [String: NSTextField] = [:]
    private var statusLabel: NSTextField!
    private var destructCheck: NSButton?
    private var destructCount: NSTextField?

    enum Mode: CaseIterable {
        case create
        case open
        case password
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        buildMenu()
        buildWindow()
        show(.create)
        resetWindowFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.resetWindowFrame()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        resetWindowFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L.t("menu.show"), action: #selector(showMainWindow), keyEquivalent: "0"))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PDF-Safe-Test"
        window.minSize = windowSize
        window.maxSize = windowSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false

        root = NSView(frame: NSRect(origin: .zero, size: windowSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(hex: 0xEEF2F6).cgColor
        window.contentView = root

        sidebar = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: windowSize.height))
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(hex: 0x111827).cgColor
        root.addSubview(sidebar)

        content = NSView(frame: NSRect(x: sidebarWidth, y: 0, width: windowSize.width - sidebarWidth, height: windowSize.height))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(hex: 0xEEF2F6).cgColor
        root.addSubview(content)

        buildSidebar()
    }

    private func resetWindowFrame() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1400, height: 900)
        let frame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
        window.setFrame(frame, display: true)
    }

    @objc private func showMainWindow() {
        resetWindowFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSidebar() {
        sidebar.subviews.forEach { $0.removeFromSuperview() }

        addShieldLogo(parent: sidebar, x: 28, top: 38)

        _ = fixedLabel("PDF-Protecter", x: 28, top: 110, w: 190, h: 28, size: 21, weight: .bold, color: .white, parent: sidebar)
        _ = fixedLabel(L.t("app.subtitle"), x: 28, top: 144, w: 190, h: 22, size: 12, weight: .regular, color: NSColor(hex: 0x98A2B3), parent: sidebar)

        addNav(.create, title: L.t("nav.create"), subtitle: L.t("nav.create.sub"), top: 194)
        addNav(.open, title: L.t("nav.open"), subtitle: L.t("nav.open.sub"), top: 268)
        addNav(.password, title: L.t("nav.password"), subtitle: L.t("nav.password.sub"), top: 342)

        let note = fixedLabel(
            L.t("sidebar.note"),
            x: 28,
            top: 648,
            w: 200,
            h: 70,
            size: 11,
            weight: .regular,
            color: NSColor(hex: 0x98A2B3),
            parent: sidebar
        )
        note.maximumNumberOfLines = 3
    }

    private func addNav(_ mode: Mode, title: String, subtitle: String, top: CGFloat) {
        let button = NSButton(frame: rect(x: 16, top: top, w: 218, h: 58, parentHeight: windowSize.height))
        button.title = ""
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = #selector(navClicked(_:))
        button.tag = Mode.allCases.firstIndex(of: mode) ?? 0
        sidebar.addSubview(button)
        navButtons[mode] = button

        let titleLabel = fixedLabel(title, x: 34, top: top + 8, w: 160, h: 22, size: 13, weight: .bold, color: .white, parent: sidebar)
        let subtitleLabel = fixedLabel(subtitle, x: 34, top: top + 34, w: 190, h: 18, size: 10, weight: .regular, color: NSColor(hex: 0x98A2B3), parent: sidebar)
        navTitleLabels[mode] = titleLabel
        navSubtitleLabels[mode] = subtitleLabel
        sidebar.addSubview(button, positioned: .above, relativeTo: titleLabel)
    }

    @objc private func navClicked(_ sender: NSButton) {
        show(Mode.allCases[sender.tag])
    }

    private func show(_ mode: Mode) {
        currentMode = mode
        fields.removeAll()
        destructCheck = nil
        destructCount = nil
        content.subviews.forEach { $0.removeFromSuperview() }
        navButtons.forEach { key, button in
            button.layer?.backgroundColor = (key == mode ? NSColor(hex: 0x2563EB) : NSColor.clear).cgColor
        }
        switch mode {
        case .create: createPage()
        case .open: openPage()
        case .password: passwordPage()
        }
    }

    private func pageHeader(_ eyebrow: String, _ title: String, _ subtitle: String) {
        _ = fixedLabel(eyebrow, x: 40, top: 40, w: 260, h: 22, size: 12, weight: .bold, color: NSColor(hex: 0x2563EB), parent: content)
        _ = fixedLabel(title, x: 40, top: 76, w: 260, h: 42, size: 31, weight: .bold, color: NSColor(hex: 0x111827), parent: content)
        _ = fixedLabel(subtitle, x: 40, top: 126, w: 640, h: 24, size: 13, weight: .regular, color: NSColor(hex: 0x667085), parent: content)

        let card = NSView(frame: rect(x: 40, top: 178, w: 650, h: cardHeight, parentHeight: windowSize.height))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.borderColor = NSColor(hex: 0xD8DEE8).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 10
        card.identifier = NSUserInterfaceItemIdentifier("card")
        content.addSubview(card)
    }

    private var card: NSView {
        content.subviews.first { $0.identifier?.rawValue == "card" }!
    }

    private func createPage() {
        pageHeader(L.t("header.create"), L.t("create.title"), L.t("create.subtitle"))
        pathRow("real", L.t("field.real"), top: 220, button: L.t("button.choose")) { [weak self] in self?.chooseReal() }
        pathRow("decoy", L.t("field.decoy"), top: 276, button: L.t("button.choose")) { [weak self] in self?.chooseDecoy() }
        pathRow("out", L.t("field.container"), top: 332, button: L.t("button.saveAs")) { [weak self] in self?.chooseCreateOut() }
        passwordRow("password", L.t("field.password"), top: 400)
        passwordRow("confirm", L.t("field.confirm"), top: 456)

        _ = fixedLabel(L.t("field.policy"), x: 32, top: 340, w: 86, h: 24, size: 13, weight: .bold, color: NSColor(hex: 0x111827), parent: card)
        let check = NSButton(checkboxWithTitle: L.t("policy.selfDestruct"), target: nil, action: nil)
        check.frame = rect(x: 140, top: 334, w: 290, h: 30, parentHeight: cardHeight)
        check.state = .on
        card.addSubview(check)
        destructCheck = check
        let count = NSTextField(frame: rect(x: 440, top: 336, w: 52, h: 28, parentHeight: cardHeight))
        count.stringValue = "3"
        count.alignment = .center
        card.addSubview(count)
        destructCount = count
        _ = fixedLabel(L.t("unit.times"), x: 500, top: 340, w: 28, h: 22, size: 12, weight: .regular, color: NSColor(hex: 0x667085), parent: card)
        footer(top: 430, button: L.t("button.create")) { [weak self] in self?.createContainer() }
    }

    private func openPage() {
        pageHeader(L.t("header.open"), L.t("open.title"), L.t("open.subtitle"))
        pathRow("container", L.t("field.container"), top: 238, button: L.t("button.choose")) { [weak self] in self?.chooseContainer() }
        pathRow("out", L.t("field.export"), top: 294, button: L.t("button.saveAs")) { [weak self] in self?.chooseOpenOut() }
        passwordRow("password", L.t("field.password"), top: 362)
        footer(top: 374, button: L.t("button.export")) { [weak self] in self?.openContainer() }
    }

    private func passwordPage() {
        pageHeader(L.t("header.password"), L.t("password.title"), L.t("password.subtitle"))
        pathRow("container", L.t("field.container"), top: 212, button: L.t("button.choose")) { [weak self] in self?.chooseContainer() }
        pathRow("decoy", L.t("field.replaceDecoy"), top: 268, button: L.t("button.optional")) { [weak self] in self?.chooseDecoy() }
        pathRow("out", L.t("field.saveAs"), top: 324, button: L.t("button.saveAs")) { [weak self] in self?.choosePasswordOut() }
        passwordRow("current", L.t("field.currentPassword"), top: 392)
        passwordRow("new", L.t("field.newPassword"), top: 448)
        passwordRow("confirm", L.t("field.confirmPassword"), top: 504)
        footer(top: 430, button: L.t("button.update")) { [weak self] in self?.changePassword() }
    }

    private func pathRow(_ key: String, _ label: String, top: CGFloat, button: String, action: @escaping () -> Void) {
        let localTop = top - 178 + 28
        _ = fixedLabel(label, x: 32, top: localTop + 8, w: 86, h: 24, size: 13, weight: .bold, color: NSColor(hex: 0x111827), parent: card)
        let field = NSTextField(frame: rect(x: 140, top: localTop, w: 370, h: 40, parentHeight: cardHeight))
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        card.addSubview(field)
        fields[key] = field
        let b = actionButton(button, frame: rect(x: 524, top: localTop, w: 86, h: 40, parentHeight: cardHeight), action: action)
        card.addSubview(b)
    }

    private func passwordRow(_ key: String, _ label: String, top: CGFloat) {
        let localTop = top - 178 + 28
        _ = fixedLabel(label, x: 32, top: localTop + 8, w: 86, h: 24, size: 13, weight: .bold, color: NSColor(hex: 0x111827), parent: card)
        let field = NSSecureTextField(frame: rect(x: 140, top: localTop, w: 470, h: 40, parentHeight: cardHeight))
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        card.addSubview(field)
        fields[key] = field
    }

    private func footer(top: CGFloat, button: String, action: @escaping () -> Void) {
        let line = NSBox(frame: rect(x: 32, top: top, w: 586, h: 1, parentHeight: cardHeight))
        line.boxType = .separator
        card.addSubview(line)
        statusLabel = fixedLabel(L.t("status.ready"), x: 32, top: top + 30, w: 390, h: 30, size: 12, weight: .regular, color: NSColor(hex: 0x667085), parent: card)
        let b = actionButton(button, frame: rect(x: 470, top: top + 24, w: 140, h: 42, parentHeight: cardHeight), action: action)
        b.keyEquivalent = "\r"
        card.addSubview(b)
    }

    private func chooseReal() {
        if let path = openFile(title: L.t("dialog.chooseReal"), types: ["pdf"]) {
            set("real", path)
            if value("out").isEmpty {
                set("out", URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("safe").path)
            }
        }
    }

    private func chooseDecoy() {
        if let path = openFile(title: L.t("dialog.chooseDecoy"), types: ["pdf"]) {
            set("decoy", path)
        }
    }

    private func chooseCreateOut() {
        if let path = saveFile(title: L.t("dialog.saveContainer"), name: "protected.safe") {
            set("out", path)
        }
    }

    private func chooseContainer() {
        if let path = openFile(title: L.t("dialog.chooseContainer"), types: ["safe"]) {
            set("container", path)
            if value("out").isEmpty {
                let url = URL(fileURLWithPath: path)
                if currentMode == .open {
                    set("out", url.deletingPathExtension().appendingPathExtension("pdf").path)
                } else {
                    set("out", url.deletingLastPathComponent().appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-updated.safe").path)
                }
            }
        }
    }

    private func chooseOpenOut() {
        if let path = saveFile(title: L.t("dialog.saveExport"), name: "exported.pdf") {
            set("out", path)
        }
    }

    private func choosePasswordOut() {
        if let path = saveFile(title: L.t("dialog.saveUpdated"), name: "protected-updated.safe") {
            set("out", path)
        }
    }

    private func createContainer() {
        do {
            try require(value("real"), L.t("error.chooseReal"))
            try require(value("decoy"), L.t("error.chooseDecoy"))
            try require(value("out"), L.t("error.chooseOutput"))
            try require(value("password"), L.t("error.enterPassword"))
            guard value("password") == value("confirm") else { throw AppError(L.t("error.passwordMismatch")) }
            var args = ["create", "--real", value("real"), "--decoy", value("decoy"), "--out", value("out"), "--password", value("password")]
            if destructCheck?.state == .on {
                args.append(contentsOf: ["--self-destruct-after", destructCount?.stringValue ?? "3"])
            }
            _ = try runTool(args)
            statusLabel.stringValue = "\(L.t("status.created"))\(value("out"))"
            alert(L.t("alert.created.title"), L.t("alert.created.message"))
        } catch {
            statusLabel.stringValue = L.t("status.createFailed")
            alert(L.t("alert.createFailed"), error.localizedDescription)
        }
    }

    private func openContainer() {
        do {
            try require(value("container"), L.t("error.chooseContainer"))
            try require(value("out"), L.t("error.chooseExport"))
            try require(value("password"), L.t("error.enterPassword"))
            let out = try runTool(["open", "--in", value("container"), "--out", value("out"), "--password", value("password")])
            statusLabel.stringValue = "\(L.t("status.exported"))\(value("out"))"
            NSWorkspace.shared.open(URL(fileURLWithPath: value("out")))
            alert(L.t("alert.exported.title"), out.isEmpty ? L.t("alert.exported.message") : "\(out)\n\n\(L.t("alert.exported.tip"))")
        } catch {
            statusLabel.stringValue = L.t("status.openFailed")
            alert(L.t("alert.openFailed"), error.localizedDescription)
        }
    }

    private func changePassword() {
        do {
            try require(value("container"), L.t("error.chooseContainer"))
            try require(value("out"), L.t("error.chooseOutput"))
            try require(value("current"), L.t("error.enterCurrent"))
            try require(value("new"), L.t("error.enterNew"))
            guard value("new") == value("confirm") else { throw AppError(L.t("error.newPasswordMismatch")) }
            var args = ["change-password", "--in", value("container"), "--out", value("out"), "--current-password", value("current"), "--new-password", value("new")]
            if !value("decoy").isEmpty {
                args.append(contentsOf: ["--decoy", value("decoy")])
            }
            _ = try runTool(args)
            statusLabel.stringValue = "\(L.t("status.updated"))\(value("out"))"
            alert(L.t("alert.updated.title"), L.t("alert.updated.message"))
        } catch {
            statusLabel.stringValue = L.t("status.updateFailed")
            alert(L.t("alert.updateFailed"), error.localizedDescription)
        }
    }

    private func value(_ key: String) -> String {
        fields[key]?.stringValue ?? ""
    }

    private func set(_ key: String, _ value: String) {
        fields[key]?.stringValue = value
    }

    private func require(_ value: String, _ message: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError(message)
        }
    }

    private func runTool(_ args: [String]) throws -> String {
        guard let script = Bundle.main.path(forResource: "pdf_protecter", ofType: "py") else {
            throw AppError(L.t("error.coreMissing"))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script] + args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw AppError(err.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "error: ", with: ""))
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openFile(title: String, types: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = types
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func saveFile(title: String, name: String) -> String? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L.t("button.ok"))
        alert.beginSheetModal(for: window)
    }
}

private func rect(x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, parentHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: parentHeight - top - h, width: w, height: h)
}

@discardableResult
private func fixedLabel(_ text: String, x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, parent: NSView) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.frame = rect(x: x, top: top, w: w, h: h, parentHeight: parent.bounds.height)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.maximumNumberOfLines = 0
    parent.addSubview(label)
    return label
}

private func actionButton(_ title: String, frame: NSRect, action: @escaping () -> Void) -> NSButton {
    let sleeve = ClosureSleeve(action)
    let button = NSButton(title: title, target: sleeve, action: #selector(ClosureSleeve.invoke))
    button.frame = frame
    button.bezelStyle = .rounded
    button.font = .boldSystemFont(ofSize: 12)
    objc_setAssociatedObject(button, Unmanaged.passUnretained(button).toOpaque(), sleeve, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return button
}

private func addShieldLogo(parent: NSView, x: CGFloat, top: CGFloat) {
    let logo = ShieldLogoView(frame: rect(x: x, top: top, w: 54, h: 54, parentHeight: parent.bounds.height))
    parent.addSubview(logo)
}

final class ShieldLogoView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: bounds).fill()

        let shield = NSBezierPath()
        let w = bounds.width
        let h = bounds.height
        shield.move(to: NSPoint(x: w * 0.5, y: h * 0.82))
        shield.line(to: NSPoint(x: w * 0.75, y: h * 0.70))
        shield.line(to: NSPoint(x: w * 0.70, y: h * 0.38))
        shield.curve(
            to: NSPoint(x: w * 0.5, y: h * 0.16),
            controlPoint1: NSPoint(x: w * 0.68, y: h * 0.28),
            controlPoint2: NSPoint(x: w * 0.60, y: h * 0.20)
        )
        shield.curve(
            to: NSPoint(x: w * 0.30, y: h * 0.38),
            controlPoint1: NSPoint(x: w * 0.40, y: h * 0.20),
            controlPoint2: NSPoint(x: w * 0.32, y: h * 0.28)
        )
        shield.line(to: NSPoint(x: w * 0.25, y: h * 0.70))
        shield.close()
        NSColor(hex: 0xDC2626).setFill()
        shield.fill()

        NSColor.white.setStroke()
        let check = NSBezierPath()
        check.lineWidth = 3
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: w * 0.38, y: h * 0.48))
        check.line(to: NSPoint(x: w * 0.48, y: h * 0.38))
        check.line(to: NSPoint(x: w * 0.64, y: h * 0.58))
        check.stroke()
    }
}

final class ClosureSleeve: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

final class Localizer {
    private let language: String

    init() {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        language = preferred.hasPrefix("zh") ? "zh" : "en"
    }

    func t(_ key: String) -> String {
        let table = language == "zh" ? Self.zh : Self.en
        return table[key] ?? Self.en[key] ?? key
    }

    private static let zh: [String: String] = [
        "menu.show": "显示主窗口",
        "menu.quit": "退出 PDF-Safe-Test",
        "app.subtitle": "PDF 安全容器",
        "nav.create": "保护 PDF",
        "nav.create.sub": "创建带伪装文件的安全容器",
        "nav.open": "打开容器",
        "nav.open.sub": "按密码导出真实或伪装文件",
        "nav.password": "修改密码",
        "nav.password.sub": "更新容器密码和伪装文件",
        "sidebar.note": "本地处理，不上传文件\n错误密码可导出伪装 PDF\n可设置 3 次错误后销毁真实内容",
        "header.create": "创建容器",
        "header.open": "打开容器",
        "header.password": "修改密码",
        "create.title": "保护 PDF",
        "create.subtitle": "把真实 PDF 和伪装 PDF 打包成一个安全容器，密码错误时只导出伪装 PDF。",
        "open.title": "打开容器",
        "open.subtitle": "正确密码导出真实 PDF；错误密码导出伪装 PDF，并记录错误次数。",
        "password.title": "修改密码",
        "password.subtitle": "用当前密码解锁后，生成一个使用新密码的新容器，也可以替换伪装 PDF。",
        "field.real": "真实 PDF",
        "field.decoy": "伪装 PDF",
        "field.container": "安全容器",
        "field.password": "访问密码",
        "field.confirm": "确认密码",
        "field.policy": "错误策略",
        "field.export": "导出 PDF",
        "field.replaceDecoy": "替换伪装",
        "field.saveAs": "保存为",
        "field.currentPassword": "当前密码",
        "field.newPassword": "新密码",
        "field.confirmPassword": "确认密码",
        "policy.selfDestruct": "密码错误达到次数后销毁容器内真实内容",
        "unit.times": "次",
        "button.choose": "选择",
        "button.saveAs": "另存为",
        "button.optional": "可选",
        "button.create": "创建容器",
        "button.export": "导出 PDF",
        "button.update": "更新密码",
        "button.ok": "好",
        "dialog.chooseReal": "选择真实 PDF",
        "dialog.chooseDecoy": "选择伪装 PDF",
        "dialog.saveContainer": "保存安全容器",
        "dialog.chooseContainer": "选择安全容器",
        "dialog.saveExport": "保存导出的 PDF",
        "dialog.saveUpdated": "保存更新后的容器",
        "status.ready": "准备就绪",
        "status.created": "已创建安全容器：",
        "status.exported": "已导出普通 PDF：",
        "status.updated": "已更新：",
        "status.createFailed": "创建失败",
        "status.openFailed": "打开失败",
        "status.updateFailed": "更新失败",
        "alert.created.title": "创建完成",
        "alert.created.message": "已创建 .safe 安全容器。\n\nmacOS 预览不能直接打开 .safe。需要在本 App 的「打开容器」里选择它，再导出普通 PDF。",
        "alert.exported.title": "导出完成",
        "alert.exported.message": "普通 PDF 已导出，可以用 macOS 预览打开。",
        "alert.exported.tip": "导出的 .pdf 可以用 macOS 预览打开。",
        "alert.updated.title": "更新完成",
        "alert.updated.message": "安全容器密码已更新。",
        "alert.createFailed": "创建失败",
        "alert.openFailed": "打开失败",
        "alert.updateFailed": "更新失败",
        "error.chooseReal": "请选择真实 PDF。",
        "error.chooseDecoy": "请选择伪装 PDF。",
        "error.chooseOutput": "请选择保存位置。",
        "error.enterPassword": "请输入访问密码。",
        "error.passwordMismatch": "两次输入的密码不一致。",
        "error.chooseContainer": "请选择 .safe 安全容器。",
        "error.chooseExport": "请选择导出 PDF 的保存位置。",
        "error.enterCurrent": "请输入当前密码。",
        "error.enterNew": "请输入新密码。",
        "error.newPasswordMismatch": "两次输入的新密码不一致。",
        "error.coreMissing": "应用包缺少加密核心文件。"
    ]

    private static let en: [String: String] = [
        "menu.show": "Show Main Window",
        "menu.quit": "Quit PDF-Safe-Test",
        "app.subtitle": "PDF security container",
        "nav.create": "Protect PDF",
        "nav.create.sub": "Create a secure decoy container",
        "nav.open": "Open Container",
        "nav.open.sub": "Export the real or decoy PDF",
        "nav.password": "Change Password",
        "nav.password.sub": "Update password and decoy PDF",
        "sidebar.note": "Local processing only\nWrong passwords export decoy PDF\nOptional destruction after 3 wrong tries",
        "header.create": "CREATE CONTAINER",
        "header.open": "OPEN CONTAINER",
        "header.password": "CHANGE PASSWORD",
        "create.title": "Protect PDF",
        "create.subtitle": "Package a real PDF and a decoy PDF into a secure container.",
        "open.title": "Open Container",
        "open.subtitle": "Correct passwords export the real PDF; wrong passwords export the decoy.",
        "password.title": "Change Password",
        "password.subtitle": "Unlock with the current password and create a new container.",
        "field.real": "Real PDF",
        "field.decoy": "Decoy PDF",
        "field.container": "Container",
        "field.password": "Password",
        "field.confirm": "Confirm",
        "field.policy": "Policy",
        "field.export": "Export PDF",
        "field.replaceDecoy": "New Decoy",
        "field.saveAs": "Save As",
        "field.currentPassword": "Current",
        "field.newPassword": "New Password",
        "field.confirmPassword": "Confirm",
        "policy.selfDestruct": "Destroy real payload after wrong passwords",
        "unit.times": "tries",
        "button.choose": "Choose",
        "button.saveAs": "Save As",
        "button.optional": "Optional",
        "button.create": "Create",
        "button.export": "Export PDF",
        "button.update": "Update",
        "button.ok": "OK",
        "dialog.chooseReal": "Choose Real PDF",
        "dialog.chooseDecoy": "Choose Decoy PDF",
        "dialog.saveContainer": "Save Secure Container",
        "dialog.chooseContainer": "Choose Secure Container",
        "dialog.saveExport": "Save Exported PDF",
        "dialog.saveUpdated": "Save Updated Container",
        "status.ready": "Ready",
        "status.created": "Created container: ",
        "status.exported": "Exported PDF: ",
        "status.updated": "Updated: ",
        "status.createFailed": "Create failed",
        "status.openFailed": "Open failed",
        "status.updateFailed": "Update failed",
        "alert.created.title": "Created",
        "alert.created.message": "Created a .safe container.\n\nmacOS Preview cannot open .safe directly. Use Open Container to export a normal PDF.",
        "alert.exported.title": "Exported",
        "alert.exported.message": "A normal PDF was exported and can be opened in macOS Preview.",
        "alert.exported.tip": "The exported .pdf can be opened in macOS Preview.",
        "alert.updated.title": "Updated",
        "alert.updated.message": "The container password was updated.",
        "alert.createFailed": "Create Failed",
        "alert.openFailed": "Open Failed",
        "alert.updateFailed": "Update Failed",
        "error.chooseReal": "Choose the real PDF.",
        "error.chooseDecoy": "Choose the decoy PDF.",
        "error.chooseOutput": "Choose an output path.",
        "error.enterPassword": "Enter a password.",
        "error.passwordMismatch": "Passwords do not match.",
        "error.chooseContainer": "Choose a .safe container.",
        "error.chooseExport": "Choose an export PDF path.",
        "error.enterCurrent": "Enter the current password.",
        "error.enterNew": "Enter the new password.",
        "error.newPasswordMismatch": "New passwords do not match.",
        "error.coreMissing": "The app package is missing the encryption core."
    ]
}

struct AppError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
