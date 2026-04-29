import AppKit

class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var screenPicker: NSPopUpButton!
    private var splitView: SplitEditorView!
    private var instructionLabel: NSTextField!
    private var splitHBtn: NSButton!
    private var splitVBtn: NSButton!
    private var splitH3Btn: NSButton!
    private var splitV3Btn: NSButton!
    private var removeBtn: NSButton!

    private var config: ScreenDividerConfig
    private let configManager: ConfigManager
    private var onConfigChanged: ((ScreenDividerConfig) -> Void)?
    var willOpen: (() -> Void)?
    var didClose: (() -> Void)?

    private var selectedScreenIndex: Int = 0

    init(configManager: ConfigManager, config: ScreenDividerConfig, onConfigChanged: @escaping (ScreenDividerConfig) -> Void) {
        self.configManager = configManager
        self.config = config
        self.onConfigChanged = onConfigChanged
        super.init()
        ensureAllScreens()
        buildWindow()
    }

    func showWindow() {
        willOpen?()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadScreen(at: 0)
    }

    private func ensureAllScreens() {
        for screen in NSScreen.screens {
            let name = screen.localizedName
            if !config.screens.contains(where: { $0.screenName == name }) {
                let root: SplitNode = config.screens.first?.root ??
                    .split(direction: .vertical, ratio: 0.5,
                           first: .zone(label: "1"), second: .zone(label: "2"))
                config.screens.append(ScreenLayout(screenName: name, root: root))
            }
        }
        if config.screens.isEmpty {
            config.screens.append(ScreenLayout(screenName: "default", root: .zone(label: "1")))
        }
    }

    private func autoSave() {
        configManager.save(config)
        onConfigChanged?(config)
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Screen Divider — Layout Editor"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false  // Prevent deallocation on close
        window.minSize = NSSize(width: 540, height: 420)

        let content = window.contentView!
        let m: CGFloat = 16

        // Screen picker
        let screenLabel = NSTextField(labelWithString: "Screen:")
        screenLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        screenLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(screenLabel)

        screenPicker = NSPopUpButton()
        screenPicker.translatesAutoresizingMaskIntoConstraints = false
        for layout in config.screens {
            screenPicker.addItem(withTitle: layout.screenName)
        }
        screenPicker.target = self
        screenPicker.action = #selector(screenChanged)
        content.addSubview(screenPicker)

        // Instructions
        instructionLabel = NSTextField(labelWithString: "Click a zone, then split or merge it. Changes apply instantly.")
        instructionLabel.font = NSFont.systemFont(ofSize: 12)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(instructionLabel)

        // Split editor
        splitView = SplitEditorView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.onSelectionChanged = { [weak self] has in self?.updateButtons(has) }
        splitView.onTreeChanged = { [weak self] newRoot in
            guard let self = self else { return }
            self.config.screens[self.selectedScreenIndex].root = newRoot
            self.autoSave()
        }
        content.addSubview(splitView)

        // Buttons
        splitHBtn = makeBtn("Split \u{2500} Half", #selector(doSplitH2))
        splitVBtn = makeBtn("Split \u{2502} Half", #selector(doSplitV2))
        splitH3Btn = makeBtn("Split \u{2500} Thirds", #selector(doSplitH3))
        splitV3Btn = makeBtn("Split \u{2502} Thirds", #selector(doSplitV3))
        removeBtn = makeBtn("Merge Back", #selector(doRemove))

        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!, removeBtn!] {
            b.isEnabled = false
            content.addSubview(b)
        }

        NSLayoutConstraint.activate([
            screenLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            screenLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            screenPicker.leadingAnchor.constraint(equalTo: screenLabel.trailingAnchor, constant: 8),
            screenPicker.centerYAnchor.constraint(equalTo: screenLabel.centerYAnchor),

            instructionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            instructionLabel.topAnchor.constraint(equalTo: screenLabel.bottomAnchor, constant: 6),

            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            splitView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 10),
            splitView.bottomAnchor.constraint(equalTo: splitHBtn!.topAnchor, constant: -14),

            splitHBtn!.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            splitHBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitVBtn!.leadingAnchor.constraint(equalTo: splitHBtn!.trailingAnchor, constant: 6),
            splitVBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitH3Btn!.leadingAnchor.constraint(equalTo: splitVBtn!.trailingAnchor, constant: 6),
            splitH3Btn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitV3Btn!.leadingAnchor.constraint(equalTo: splitH3Btn!.trailingAnchor, constant: 6),
            splitV3Btn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            removeBtn!.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            removeBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
        ])
    }

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = NSFont.systemFont(ofSize: 11)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func updateButtons(_ hasSelection: Bool) {
        let canMerge = hasSelection && (splitView.selectedPath?.count ?? 0) > 0
        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!] { b.isEnabled = hasSelection }
        removeBtn.isEnabled = canMerge
    }

    private func loadScreen(at index: Int) {
        guard index >= 0 && index < config.screens.count else { return }
        selectedScreenIndex = index
        splitView.root = config.screens[index].root
        splitView.selectedPath = nil
        updateButtons(false)
    }

    @objc private func screenChanged() { loadScreen(at: screenPicker.indexOfSelectedItem) }
    @objc private func doSplitH2() { splitView.splitSelected(direction: .horizontal, parts: 2); updateButtons(splitView.selectedPath != nil) }
    @objc private func doSplitV2() { splitView.splitSelected(direction: .vertical, parts: 2); updateButtons(splitView.selectedPath != nil) }
    @objc private func doSplitH3() { splitView.splitSelected(direction: .horizontal, parts: 3); updateButtons(splitView.selectedPath != nil) }
    @objc private func doSplitV3() { splitView.splitSelected(direction: .vertical, parts: 3); updateButtons(splitView.selectedPath != nil) }
    @objc private func doRemove() { splitView.removeSelected(); updateButtons(splitView.selectedPath != nil) }

    func windowWillClose(_ notification: Notification) { didClose?() }
}

// MARK: - Visual Split Editor View

class SplitEditorView: NSView {
    var root: SplitNode = .zone(label: "1") { didSet { needsDisplay = true } }
    var selectedPath: [Int]? = nil { didSet { needsDisplay = true } }
    var onSelectionChanged: ((Bool) -> Void)?
    var onTreeChanged: ((SplitNode) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.insetBy(dx: 1, dy: 1)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: area, xRadius: 6, yRadius: 6).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: area, xRadius: 6, yRadius: 6).stroke()
        drawNode(root, in: area.insetBy(dx: 1, dy: 1), path: [])
    }

    private func drawNode(_ node: SplitNode, in rect: CGRect, path: [Int]) {
        switch node {
        case .zone(let label):
            let isSel = selectedPath != nil && path == selectedPath!
            let r = rect.insetBy(dx: 2, dy: 2)

            (isSel ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.controlAccentColor.withAlphaComponent(0.08)).setFill()
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            p.fill()
            (isSel ? NSColor.controlAccentColor : NSColor.gridColor).setStroke()
            p.lineWidth = isSel ? 3 : 1
            p.stroke()

            let fs = max(10, min(20, min(r.width, r.height) / 3))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fs, weight: isSel ? .bold : .medium),
                .foregroundColor: isSel ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            ]
            let sz = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(in: NSRect(x: r.midX - sz.width/2, y: r.midY - sz.height/2,
                                                 width: sz.width+2, height: sz.height), withAttributes: attrs)

        case .split(let dir, let ratio, let first, let second):
            let (r1, r2) = splitRect(rect, direction: dir, ratio: ratio)
            drawNode(first, in: r1, path: path + [0])
            drawNode(second, in: r2, path: path + [1])
        }
    }

    private func splitRect(_ rect: CGRect, direction: SplitDirection, ratio: Double) -> (CGRect, CGRect) {
        let r = CGFloat(ratio)
        switch direction {
        case .vertical:
            let w1 = rect.width * r
            return (CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height),
                    CGRect(x: rect.minX + w1, y: rect.minY, width: rect.width - w1, height: rect.height))
        case .horizontal:
            let h2 = rect.height * (1 - r)
            return (CGRect(x: rect.minX, y: rect.minY + h2, width: rect.width, height: rect.height - h2),
                    CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        selectedPath = findZone(root, pt, bounds.insetBy(dx: 2, dy: 2), [])
        onSelectionChanged?(selectedPath != nil)
    }

    private func findZone(_ node: SplitNode, _ pt: CGPoint, _ rect: CGRect, _ path: [Int]) -> [Int]? {
        switch node {
        case .zone: return rect.contains(pt) ? path : nil
        case .split(let d, let r, let f, let s):
            let (r1, r2) = splitRect(rect, direction: d, ratio: r)
            return findZone(f, pt, r1, path+[0]) ?? findZone(s, pt, r2, path+[1])
        }
    }

    // MARK: - Split (halves or thirds)

    func splitSelected(direction: SplitDirection, parts: Int) {
        guard let path = selectedPath, let node = getNode(at: path) else { return }
        guard case .zone = node else { return }

        let newNode: SplitNode
        if parts == 3 {
            // Split into 3: first split at 1/3, then split the second part at 1/2 (which gives 1/3 + 1/3 + 1/3)
            newNode = .split(direction: direction, ratio: 1.0/3.0,
                first: .zone(label: "a"),
                second: .split(direction: direction, ratio: 0.5,
                    first: .zone(label: "b"),
                    second: .zone(label: "c")))
        } else {
            newNode = .split(direction: direction, ratio: 0.5,
                first: .zone(label: "a"),
                second: .zone(label: "b"))
        }

        root = setNode(at: path, to: newNode)
        renumberAll()
        onTreeChanged?(root)
        selectedPath = path + [0]
        onSelectionChanged?(true)
    }

    func removeSelected() {
        guard let path = selectedPath, !path.isEmpty else { return }
        let parentPath = Array(path.dropLast())
        guard let parent = getNode(at: parentPath) else { return }
        if case .split(_, _, let f, let s) = parent {
            let keep = path.last! == 0 ? s : f
            root = setNode(at: parentPath, to: keep)
            renumberAll()
            onTreeChanged?(root)
            selectedPath = nil
            onSelectionChanged?(false)
        }
    }

    private func renumberAll() {
        var n = 1
        root = renum(root, &n)
    }

    private func renum(_ node: SplitNode, _ n: inout Int) -> SplitNode {
        switch node {
        case .zone:
            let label = "\(n)"; n += 1; return .zone(label: label)
        case .split(let d, let r, let f, let s):
            return .split(direction: d, ratio: r, first: renum(f, &n), second: renum(s, &n))
        }
    }

    private func getNode(at path: [Int]) -> SplitNode? {
        var cur = root
        for i in path {
            guard case .split(_, _, let f, let s) = cur else { return nil }
            cur = i == 0 ? f : s
        }
        return cur
    }

    private func setNode(at path: [Int], to new: SplitNode) -> SplitNode {
        return setRec(root, path, new)
    }

    private func setRec(_ node: SplitNode, _ path: [Int], _ new: SplitNode) -> SplitNode {
        if path.isEmpty { return new }
        guard case .split(let d, let r, let f, let s) = node else { return node }
        let rest = Array(path.dropFirst())
        return path[0] == 0
            ? .split(direction: d, ratio: r, first: setRec(f, rest, new), second: s)
            : .split(direction: d, ratio: r, first: f, second: setRec(s, rest, new))
    }
}
