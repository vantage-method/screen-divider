import AppKit

class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var screenPicker: NSPopUpButton!
    private var presetPicker: NSPopUpButton!
    private var splitView: SplitEditorView!
    private var splitHBtn: NSButton!
    private var splitVBtn: NSButton!
    private var splitH3Btn: NSButton!
    private var splitV3Btn: NSButton!
    private var mergeBtn: NSButton!
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
                config.screens.append(ScreenLayout(screenName: name, root: defaultRoot, grid: .defaultHalves))
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
        presetPicker.addItem(withTitle: "Presets")
        presetPicker.menu?.addItem(.separator())
        for preset in config.presets ?? [] {
            presetPicker.addItem(withTitle: preset.name)
        }
        presetPicker.selectItem(at: 0)
        deletePresetBtn.isEnabled = false
    }

    @objc private func presetSelected() {
        let idx = presetPicker.indexOfSelectedItem
        let presetIdx = idx - 2
        guard presetIdx >= 0, let presets = config.presets, presetIdx < presets.count else {
            deletePresetBtn.isEnabled = false
            return
        }
        let preset = presets[presetIdx]
        splitView.pushUndo()
        var g = preset.grid ?? GridLayout(tree: preset.root)
        g.normalize()
        splitView.setGrid(g)
        config.screens[selectedScreenIndex].grid = g
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
        let preset = LayoutPreset(name: name, root: config.screens[selectedScreenIndex].root, grid: config.screens[selectedScreenIndex].effectiveGrid)
        if config.presets == nil { config.presets = [] }
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Layout Editor"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 380)

        let content = window.contentView!
        let m: CGFloat = 24

        // ── Row 1: Screen + Presets ──
        screenPicker = NSPopUpButton()
        screenPicker.translatesAutoresizingMaskIntoConstraints = false
        screenPicker.controlSize = .large
        screenPicker.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for layout in config.screens {
            screenPicker.addItem(withTitle: layout.screenName)
        }
        screenPicker.target = self
        screenPicker.action = #selector(screenChanged)
        content.addSubview(screenPicker)

        presetPicker = NSPopUpButton()
        presetPicker.translatesAutoresizingMaskIntoConstraints = false
        presetPicker.controlSize = .large
        presetPicker.font = NSFont.systemFont(ofSize: 13)
        presetPicker.target = self
        presetPicker.action = #selector(presetSelected)
        content.addSubview(presetPicker)

        savePresetBtn = makePillBtn("Save", #selector(savePreset), color: PreferencesWindowController.brandBlue)
        content.addSubview(savePresetBtn)

        deletePresetBtn = makePillBtn("Delete", #selector(deletePreset))
        deletePresetBtn.isEnabled = false
        content.addSubview(deletePresetBtn)

        rebuildPresetPicker()

        // ── Editor (no wrapping card — just the view directly) ──
        splitView = SplitEditorView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.onSelectionChanged = { [weak self] in self?.updateButtons() }
        splitView.onGridChanged = { [weak self] newGrid in
            guard let self = self else { return }
            self.config.screens[self.selectedScreenIndex].grid = newGrid
            self.autoSave()
        }
        content.addSubview(splitView)

        // ── Bottom buttons ──
        let blue = PreferencesWindowController.brandBlue
        let purple = PreferencesWindowController.brandPurple

        splitHBtn = makePillBtn("\u{2500} Half", #selector(doSplitH2), color: blue)
        splitVBtn = makePillBtn("\u{2502} Half", #selector(doSplitV2), color: purple)
        splitH3Btn = makePillBtn("\u{2500} Thirds", #selector(doSplitH3), color: blue)
        splitV3Btn = makePillBtn("\u{2502} Thirds", #selector(doSplitV3), color: purple)
        mergeBtn = makePillBtn("Merge", #selector(doMerge))  // gradient (default)
        removeBtn = makePillBtn("Remove", #selector(doRemove), color: NSColor.systemGray)
        undoBtn = makePillBtn("Undo", #selector(doUndo))
        undoBtn.keyEquivalent = "z"
        undoBtn.keyEquivalentModifierMask = .command

        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!, mergeBtn!, removeBtn!, undoBtn!] {
            b.isEnabled = false
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let btnStack = NSStackView(views: [splitHBtn, splitVBtn, splitH3Btn, splitV3Btn, spacer, mergeBtn, removeBtn, undoBtn])
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(btnStack)

        // ── Hint ──
        let hint = NSTextField(labelWithString: "Click to select  \u{2022}  Shift-click for multi-select  \u{2022}  Merge any rectangle  \u{2022}  Click an empty cell to fill it  \u{2022}  \u{2318}Z undo")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        // ── Layout ──
        NSLayoutConstraint.activate([
            // Top row
            screenPicker.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            screenPicker.topAnchor.constraint(equalTo: content.topAnchor, constant: m + 16),

            deletePresetBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            deletePresetBtn.centerYAnchor.constraint(equalTo: screenPicker.centerYAnchor),
            savePresetBtn.trailingAnchor.constraint(equalTo: deletePresetBtn.leadingAnchor, constant: -6),
            savePresetBtn.centerYAnchor.constraint(equalTo: screenPicker.centerYAnchor),
            presetPicker.trailingAnchor.constraint(equalTo: savePresetBtn.leadingAnchor, constant: -8),
            presetPicker.centerYAnchor.constraint(equalTo: screenPicker.centerYAnchor),

            // Editor — generous margins, no card wrapper
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            splitView.topAnchor.constraint(equalTo: screenPicker.bottomAnchor, constant: 20),
            splitView.bottomAnchor.constraint(equalTo: btnStack.topAnchor, constant: -20),

            // Button row
            btnStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            btnStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            btnStack.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -12),
            btnStack.heightAnchor.constraint(equalToConstant: 34),

            // Hint
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - UI Helpers

    private func makePillBtn(_ title: String, _ action: Selector, color: NSColor? = nil) -> NSButton {
        let b = PillButton(title: title, target: self, action: action)
        if let c = color { b.solidColor = c }
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    // Brand colors matching the app icon gradient
    static let brandBlue = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.95, alpha: 1.0)
    static let brandPurple = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.90, alpha: 1.0)
    static let brandPink = NSColor(calibratedRed: 0.85, green: 0.30, blue: 0.65, alpha: 1.0)

    private func updateButtons() {
        let count = splitView.selected.count
        for b in [splitHBtn!, splitVBtn!, splitH3Btn!, splitV3Btn!] { b.isEnabled = count == 1 }
        mergeBtn.isEnabled = splitView.canMergeSelected()
        removeBtn.isEnabled = count >= 1
        undoBtn.isEnabled = splitView.canUndo
    }

    private func loadScreen(at index: Int) {
        guard index >= 0 && index < config.screens.count else { return }
        selectedScreenIndex = index
        splitView.setGrid(config.screens[index].effectiveGrid)
        splitView.clearUndo()
        updateButtons()
    }

    @objc private func screenChanged() { loadScreen(at: screenPicker.indexOfSelectedItem) }
    @objc private func doSplitH2() { splitView.splitSelected(direction: .horizontal, parts: 2); updateButtons() }
    @objc private func doSplitV2() { splitView.splitSelected(direction: .vertical, parts: 2); updateButtons() }
    @objc private func doSplitH3() { splitView.splitSelected(direction: .horizontal, parts: 3); updateButtons() }
    @objc private func doSplitV3() { splitView.splitSelected(direction: .vertical, parts: 3); updateButtons() }
    @objc private func doMerge() { splitView.mergeSelected(); updateButtons() }
    @objc private func doRemove() { splitView.removeSelected(); updateButtons() }
    @objc private func doUndo() { splitView.undo(); updateButtons() }

    func windowWillClose(_ notification: Notification) { didClose?() }
}

// MARK: - Visual Grid Editor View

class SplitEditorView: NSView {
    var grid: GridLayout = .defaultHalves { didSet { needsDisplay = true } }
    var selected: Set<Int> = [] { didSet { needsDisplay = true } }
    var onSelectionChanged: (() -> Void)?
    var onGridChanged: ((GridLayout) -> Void)?

    private var undoStack: [GridLayout] = []
    var canUndo: Bool { !undoStack.isEmpty }

    override var acceptsFirstResponder: Bool { true }
    // Grid fractions are top-origin (y=0 = top), matching the overlay and the
    // Accessibility coordinate space. Flip this view so it renders the same
    // way — otherwise the editor is vertically mirrored vs. the real screen.
    override var isFlipped: Bool { true }

    func setGrid(_ g: GridLayout) {
        grid = g
        selected = []
        needsDisplay = true
    }

    // MARK: - Undo

    func pushUndo() {
        undoStack.append(grid)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func clearUndo() { undoStack.removeAll() }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        grid = previous
        selected = []
        onGridChanged?(grid)
        onSelectionChanged?()
    }

    private func commit() {
        grid.normalize()
        onGridChanged?(grid)
        needsDisplay = true
    }

    // MARK: - Drawing

    private func viewRect(_ fractional: CGRect) -> CGRect {
        CGRect(x: bounds.minX + fractional.minX * bounds.width,
               y: bounds.minY + fractional.minY * bounds.height,
               width: fractional.width * bounds.width,
               height: fractional.height * bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let brandPurple = PreferencesWindowController.brandPurple

        // Outline only EMPTY cells (dashed) — never draw full-length grid
        // lines, which would ghost straight through a merged zone whenever a
        // track boundary is still shared by a neighbouring row/column.
        let re = grid.rowEdges(), ce = grid.colEdges()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        for r in 0..<grid.rows.count {
            for c in 0..<grid.cols.count where grid.zoneIndex(atRow: r, col: c) == nil {
                let cell = CGRect(x: ce[c], y: re[r], width: grid.cols[c], height: grid.rows[r])
                let vr = viewRect(cell).insetBy(dx: 2, dy: 2)
                let path = NSBezierPath(roundedRect: vr, xRadius: 4, yRadius: 4)
                path.lineWidth = 0.5
                path.setLineDash([3, 3], count: 2, phase: 0)
                path.stroke()
            }
        }

        for (i, z) in grid.rects().enumerated() {
            let isSel = selected.contains(i)
            let r = viewRect(z.rect).insetBy(dx: 2, dy: 2)
            let cornerRadius: CGFloat = 6

            if isSel {
                brandPurple.withAlphaComponent(0.12).setFill()
            } else {
                brandPurple.withAlphaComponent(0.03).setFill()
            }
            let p = NSBezierPath(roundedRect: r, xRadius: cornerRadius, yRadius: cornerRadius)
            p.fill()

            if isSel {
                brandPurple.withAlphaComponent(0.5).setStroke()
                p.lineWidth = 1.5
            } else {
                NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
                p.lineWidth = 0.5
            }
            p.stroke()

            let fs = max(10, min(18, min(r.width, r.height) / 4))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fs, weight: isSel ? .medium : .regular),
                .foregroundColor: isSel ? brandPurple.withAlphaComponent(0.7) : NSColor.quaternaryLabelColor
            ]
            let sz = (z.label as NSString).size(withAttributes: attrs)
            let textRect = NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2,
                                  width: sz.width + 2, height: sz.height)
            (z.label as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fp = CGPoint(x: (pt.x - bounds.minX) / bounds.width,
                         y: (pt.y - bounds.minY) / bounds.height)

        let hit = grid.rects().firstIndex { $0.rect.insetBy(dx: -0.001, dy: -0.001).contains(fp) }

        if let i = hit {
            if event.modifierFlags.contains(.shift) {
                if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
            } else {
                selected = selected == [i] ? [] : [i]
            }
        } else if let cell = grid.cell(atPoint: fp), grid.zoneIndex(atRow: cell.r, col: cell.c) == nil {
            // empty cell: create a zone there
            pushUndo()
            grid.addZone(atRow: cell.r, col: cell.c)
            commit()
            selected = []
        } else {
            selected = []
        }
        onSelectionChanged?()
    }

    // MARK: - Operations

    func canMergeSelected() -> Bool { grid.canMerge(selected) }

    func splitSelected(direction: SplitDirection, parts: Int) {
        guard selected.count == 1, let i = selected.first else { return }
        pushUndo()
        grid.splitZone(at: i, direction: direction, parts: parts)
        commit()
        selected = []
        onSelectionChanged?()
    }

    func mergeSelected() {
        guard grid.canMerge(selected) else { return }
        pushUndo()
        grid.merge(selected)
        commit()
        selected = []
        onSelectionChanged?()
    }

    func removeSelected() {
        guard !selected.isEmpty else { return }
        pushUndo()
        grid.removeZones(selected)
        commit()
        selected = []
        onSelectionChanged?()
    }
}

// MARK: - Custom Pill Button (solid color or gradient)

class PillButton: NSButton {
    /// Set to a color for a solid fill; leave nil for the gradient
    var solidColor: NSColor? { didSet { needsDisplay = true } }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        self.wantsLayer = true
        self.setButtonType(.momentaryChange)
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (title as NSString).size(withAttributes: [.font: font as Any])
        return NSSize(width: textSize.width + 28, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)

        if isEnabled {
            if let solid = solidColor {
                solid.setFill()
                path.fill()
            } else {
                // Gradient fill
                let blue = PreferencesWindowController.brandBlue
                let purple = PreferencesWindowController.brandPurple
                let pink = PreferencesWindowController.brandPink
                if let gradient = NSGradient(colors: [blue, purple, pink],
                                              atLocations: [0.0, 0.5, 1.0], colorSpace: .deviceRGB) {
                    gradient.draw(in: path, angle: 135)
                }
            }
        } else {
            NSColor.separatorColor.withAlphaComponent(0.15).setFill()
            path.fill()
        }

        // Centered title
        let color: NSColor = isEnabled ? .white : .tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: color
        ]
        let sz = (title as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: (r.width - sz.width) / 2,
            y: (r.height - sz.height) / 2,
            width: sz.width,
            height: sz.height)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        alphaValue = 0.7
        super.mouseDown(with: event)
        alphaValue = 1.0
    }
}
