import AppKit

class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var screenPicker: NSPopUpButton!
    private var presetPicker: NSPopUpButton!
    private var splitView: SplitEditorView!
    private var instructionLabel: NSTextField!
    private var splitHBtn: NSButton!
    private var splitVBtn: NSButton!
    private var splitH3Btn: NSButton!
    private var splitV3Btn: NSButton!
    private var removeBtn: NSButton!
    private var undoBtn: NSButton!
    private var savePresetBtn: NSButton!
    private var deletePresetBtn: NSButton!

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

    func showWindow(selectScreenIndex: Int = 0) {
        willOpen?()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let idx = min(selectScreenIndex, config.screens.count - 1)
        screenPicker.selectItem(at: max(idx, 0))
        loadScreen(at: max(idx, 0))
    }

    func refreshConfig(_ newConfig: ScreenDividerConfig) {
        self.config = newConfig
        ensureAllScreens()
        screenPicker.removeAllItems()
        for layout in config.screens {
            screenPicker.addItem(withTitle: layout.screenName)
        }
        rebuildPresetPicker()
    }

    private func ensureAllScreens() {
        let connectedNames = Set(NSScreen.screens.map { $0.localizedName })
        config.screens.removeAll { !connectedNames.contains($0.screenName) }
        for screen in NSScreen.screens {
            let name = screen.localizedName
            if !config.screens.contains(where: { $0.screenName == name }) {
                let defaultRoot: SplitNode = .split(direction: .vertical, ratio: 0.5,
                    first: .zone(label: "1"), second: .zone(label: "2"))
                config.screens.append(ScreenLayout(screenName: name, root: defaultRoot))
            }
        }
    }

    private func autoSave() {
        configManager.save(config)
        onConfigChanged?(config)
    }

    // MARK: - Presets

    private func rebuildPresetPicker() {
        presetPicker.removeAllItems()
        presetPicker.addItem(withTitle: "Presets...")
        presetPicker.menu?.addItem(.separator())
        for preset in config.presets ?? [] {
            presetPicker.addItem(withTitle: preset.name)
        }
        presetPicker.selectItem(at: 0)
        deletePresetBtn.isEnabled = false
    }

    @objc private func presetSelected() {
        let idx = presetPicker.indexOfSelectedItem
        // Account for header item + separator
        let presetIdx = idx - 2
        guard presetIdx >= 0, let presets = config.presets, presetIdx < presets.count else {
            deletePresetBtn.isEnabled = false
            return
        }
        let preset = presets[presetIdx]
        splitView.pushUndo()
        splitView.root = preset.root
        splitView.selectedPaths = []
        splitView.renumberAll()
        splitView.onTreeChanged?(splitView.root)
        config.screens[selectedScreenIndex].root = splitView.root
        autoSave()
        updateButtons()
        deletePresetBtn.isEnabled = true
    }

    @objc private func savePreset() {
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Enter a name for this layout preset:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = "\(config.screens[selectedScreenIndex].screenName) layout"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let preset = LayoutPreset(name: name, root: config.screens[selectedScreenIndex].root)
        if config.presets == nil { config.presets = [] }
        // Replace existing preset with same name, or append
        if let existing = config.presets!.firstIndex(where: { $0.name == name }) {
            config.presets![existing] = preset
        } else {
            config.presets!.append(preset)
        }
        autoSave()
        rebuildPresetPicker()
    }

    @objc private func deletePreset() {
        let idx = presetPicker.indexOfSelectedItem - 2
        guard idx >= 0, config.presets != nil, idx < config.presets!.count else { return }
        let name = config.presets![idx].name

        let alert = NSAlert()
        alert.messageText = "Delete Preset"
        alert.informativeText = "Delete preset \"\(name)\"?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        config.presets!.remove(at: idx)
        if config.presets!.isEmpty { config.presets = nil }
        autoSave()
        rebuildPresetPicker()
    }

    // MARK: - Build Window

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Screen Divider — Layout Editor"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 440)

        let content = window.contentView!
        let m: CGFloat = 16

        // Row 1: Screen picker
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

        // Row 1 right side: Preset picker + save/delete
        presetPicker = NSPopUpButton()
        presetPicker.translatesAutoresizingMaskIntoConstraints = false
        presetPicker.target = self
        presetPicker.action = #selector(presetSelected)
        content.addSubview(presetPicker)
        rebuildPresetPicker()

        savePresetBtn = makeBtn("Save...", #selector(savePreset))
        content.addSubview(savePresetBtn)

        deletePresetBtn = makeBtn("Delete", #selector(deletePreset))
        deletePresetBtn.isEnabled = false
        content.addSubview(deletePresetBtn)

        // Instructions
        instructionLabel = NSTextField(labelWithString: "Click a zone to select. Shift-click to multi-select. Cmd+Z to undo.")
        instructionLabel.font = NSFont.systemFont(ofSize: 12)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(instructionLabel)

        // Split editor
        splitView = SplitEditorView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.onSelectionChanged = { [weak self] in self?.updateButtons() }
        splitView.onTreeChanged = { [weak self] newRoot in
            guard let self = self else { return }
            self.config.screens[self.selectedScreenIndex].root = newRoot
            self.autoSave()
        }
        content.addSubview(splitView)

        // Bottom buttons
        splitHBtn = makeBtn("Split \u{2500} Half", #selector(doSplitH2))
        splitVBtn = makeBtn("Split \u{2502} Half", #selector(doSplitV2))
        splitH3Btn = makeBtn("Split \u{2500} Thirds", #selector(doSplitH3))
        splitV3Btn = makeBtn("Split \u{2502} Thirds", #selector(doSplitV3))
        removeBtn = makeBtn("Merge Back", #selector(doRemove))
        undoBtn = makeBtn("Undo", #selector(doUndo))
        undoBtn.keyEquivalent = "z"
        undoBtn.keyEquivalentModifierMask = .command
        undoBtn.isEnabled = false

        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!, removeBtn!, undoBtn!] {
            if b !== undoBtn { b.isEnabled = false }
            content.addSubview(b)
        }

        NSLayoutConstraint.activate([
            // Row 1: Screen + Presets
            screenLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            screenLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            screenPicker.leadingAnchor.constraint(equalTo: screenLabel.trailingAnchor, constant: 8),
            screenPicker.centerYAnchor.constraint(equalTo: screenLabel.centerYAnchor),

            deletePresetBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            deletePresetBtn.centerYAnchor.constraint(equalTo: screenLabel.centerYAnchor),
            savePresetBtn.trailingAnchor.constraint(equalTo: deletePresetBtn.leadingAnchor, constant: -4),
            savePresetBtn.centerYAnchor.constraint(equalTo: screenLabel.centerYAnchor),
            presetPicker.trailingAnchor.constraint(equalTo: savePresetBtn.leadingAnchor, constant: -6),
            presetPicker.centerYAnchor.constraint(equalTo: screenLabel.centerYAnchor),
            presetPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            // Instructions
            instructionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            instructionLabel.topAnchor.constraint(equalTo: screenLabel.bottomAnchor, constant: 6),

            // Split editor
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            splitView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 10),
            splitView.bottomAnchor.constraint(equalTo: splitHBtn!.topAnchor, constant: -14),

            // Bottom row
            splitHBtn!.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            splitHBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitVBtn!.leadingAnchor.constraint(equalTo: splitHBtn!.trailingAnchor, constant: 6),
            splitVBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitH3Btn!.leadingAnchor.constraint(equalTo: splitVBtn!.trailingAnchor, constant: 6),
            splitH3Btn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            splitV3Btn!.leadingAnchor.constraint(equalTo: splitH3Btn!.trailingAnchor, constant: 6),
            splitV3Btn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            undoBtn!.trailingAnchor.constraint(equalTo: removeBtn!.leadingAnchor, constant: -6),
            undoBtn!.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
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

    private func updateButtons() {
        let count = splitView.selectedPaths.count
        let singleSelected = count == 1
        let canMerge = count >= 1 && splitView.canMergeSelected()
        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!] { b.isEnabled = singleSelected }
        removeBtn.isEnabled = canMerge
        undoBtn.isEnabled = splitView.canUndo
    }

    private func loadScreen(at index: Int) {
        guard index >= 0 && index < config.screens.count else { return }
        selectedScreenIndex = index
        splitView.root = config.screens[index].root
        splitView.selectedPaths = []
        splitView.clearUndo()
        updateButtons()
    }

    @objc private func screenChanged() { loadScreen(at: screenPicker.indexOfSelectedItem) }
    @objc private func doSplitH2() { splitView.splitSelected(direction: .horizontal, parts: 2); updateButtons() }
    @objc private func doSplitV2() { splitView.splitSelected(direction: .vertical, parts: 2); updateButtons() }
    @objc private func doSplitH3() { splitView.splitSelected(direction: .horizontal, parts: 3); updateButtons() }
    @objc private func doSplitV3() { splitView.splitSelected(direction: .vertical, parts: 3); updateButtons() }
    @objc private func doRemove() { splitView.removeSelected(); updateButtons() }
    @objc private func doUndo() { splitView.undo(); updateButtons() }

    func windowWillClose(_ notification: Notification) { didClose?() }
}

// MARK: - Visual Split Editor View

class SplitEditorView: NSView {
    var root: SplitNode = .zone(label: "1") { didSet { needsDisplay = true } }
    var selectedPaths: [[Int]] = [] { didSet { needsDisplay = true } }
    var onSelectionChanged: (() -> Void)?
    var onTreeChanged: ((SplitNode) -> Void)?

    private var undoStack: [SplitNode] = []
    var canUndo: Bool { !undoStack.isEmpty }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Undo

    func pushUndo() {
        undoStack.append(root)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func clearUndo() {
        undoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        root = previous
        selectedPaths = []
        onTreeChanged?(root)
        onSelectionChanged?()
    }

    // MARK: - Drawing

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
            let isSel = selectedPaths.contains(path)
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

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        guard let clicked = findZone(root, pt, bounds.insetBy(dx: 2, dy: 2), []) else {
            selectedPaths = []
            onSelectionChanged?()
            return
        }

        if event.modifierFlags.contains(.shift) && !selectedPaths.isEmpty {
            // Shift-click: expand selection to cover clicked zone too.
            // Find the LCA of existing selection + new click, then select ALL
            // zones under that LCA so it forms a valid mergeable region.
            var anchors = selectedPaths
            if !anchors.contains(clicked) {
                anchors.append(clicked)
            } else {
                // Shift-clicking an already-selected zone: deselect by
                // shrinking back to just the other anchor zones that were
                // explicitly clicked. For simplicity, just deselect all.
                selectedPaths = []
                onSelectionChanged?()
                return
            }
            let lca = lowestCommonAncestor(anchors)
            if let lcaNode = getNode(at: lca) {
                selectedPaths = allLeafPaths(node: lcaNode, basePath: lca)
            }
        } else {
            selectedPaths = [clicked]
        }
        onSelectionChanged?()
    }

    private func findZone(_ node: SplitNode, _ pt: CGPoint, _ rect: CGRect, _ path: [Int]) -> [Int]? {
        switch node {
        case .zone: return rect.contains(pt) ? path : nil
        case .split(let d, let r, let f, let s):
            let (r1, r2) = splitRect(rect, direction: d, ratio: r)
            return findZone(f, pt, r1, path+[0]) ?? findZone(s, pt, r2, path+[1])
        }
    }

    // MARK: - Merge helpers

    private func lowestCommonAncestor(_ paths: [[Int]]) -> [Int] {
        guard let first = paths.first else { return [] }
        var lca = first
        for path in paths.dropFirst() {
            var common: [Int] = []
            for (a, b) in zip(lca, path) {
                if a == b { common.append(a) } else { break }
            }
            lca = common
        }
        return lca
    }

    private func allLeafPaths(node: SplitNode, basePath: [Int]) -> [[Int]] {
        switch node {
        case .zone:
            return [basePath]
        case .split(_, _, let f, let s):
            return allLeafPaths(node: f, basePath: basePath + [0]) +
                   allLeafPaths(node: s, basePath: basePath + [1])
        }
    }

    func canMergeSelected() -> Bool {
        if selectedPaths.count == 1 {
            return selectedPaths[0].count > 0
        }
        // Multi-select always forms a valid LCA group (auto-expanded on click)
        return selectedPaths.count >= 2
    }

    // MARK: - Split

    func splitSelected(direction: SplitDirection, parts: Int) {
        guard selectedPaths.count == 1, let path = selectedPaths.first,
              let node = getNode(at: path), case .zone = node else { return }

        pushUndo()
        let newNode: SplitNode
        if parts == 3 {
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
        selectedPaths = [path + [0]]
        onSelectionChanged?()
    }

    // MARK: - Merge

    func removeSelected() {
        pushUndo()

        if selectedPaths.count == 1 {
            // Single selection: merge with sibling
            let path = selectedPaths[0]
            guard !path.isEmpty else { undoStack.removeLast(); return }
            let parentPath = Array(path.dropLast())
            guard let parent = getNode(at: parentPath) else { undoStack.removeLast(); return }
            if case .split(_, _, let f, let s) = parent {
                let keep = path.last! == 0 ? s : f
                root = setNode(at: parentPath, to: keep)
                renumberAll()
                onTreeChanged?(root)
                selectedPaths = []
                onSelectionChanged?()
            }
        } else if selectedPaths.count >= 2 {
            // Multi-select: selection is always a complete LCA subtree,
            // so replace the LCA with a single zone
            let lca = lowestCommonAncestor(selectedPaths)
            root = setNode(at: lca, to: .zone(label: "1"))
            renumberAll()
            onTreeChanged?(root)
            selectedPaths = [lca]
            onSelectionChanged?()
        }
    }

    // MARK: - Tree utilities

    func renumberAll() {
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
