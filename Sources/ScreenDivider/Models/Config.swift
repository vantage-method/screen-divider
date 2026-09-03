import Foundation

// MARK: - Tree-based layout model

struct ScreenDividerConfig: Codable {
    var screens: [ScreenLayout]
    var presets: [LayoutPreset]?

    /// Find layout for a given screen, or fall back to first
    func layout(for screenName: String) -> ScreenLayout? {
        return screens.first(where: { $0.screenName == screenName })
            ?? screens.first
    }
}

struct LayoutPreset: Codable {
    var name: String
    var root: SplitNode
    var grid: GridLayout?
}

struct ScreenLayout: Codable {
    var screenName: String  // e.g. "Built-in Retina Display", "default"
    var root: SplitNode
    var grid: GridLayout?
}

enum SplitDirection: String, Codable {
    case horizontal  // splits top/bottom
    case vertical    // splits left/right
}

/// A node is either a zone (leaf) or a split into two children.
indirect enum SplitNode: Codable {
    case zone(label: String)
    case split(direction: SplitDirection, ratio: Double, first: SplitNode, second: SplitNode)

    // Custom Codable for the enum
    enum CodingKeys: String, CodingKey {
        case type, label, direction, ratio, first, second
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "zone" {
            let label = try container.decode(String.self, forKey: .label)
            self = .zone(label: label)
        } else {
            let dir = try container.decode(SplitDirection.self, forKey: .direction)
            let ratio = try container.decodeIfPresent(Double.self, forKey: .ratio) ?? 0.5
            let first = try container.decode(SplitNode.self, forKey: .first)
            let second = try container.decode(SplitNode.self, forKey: .second)
            self = .split(direction: dir, ratio: ratio, first: first, second: second)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .zone(let label):
            try container.encode("zone", forKey: .type)
            try container.encode(label, forKey: .label)
        case .split(let dir, let ratio, let first, let second):
            try container.encode("split", forKey: .type)
            try container.encode(dir, forKey: .direction)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }

    /// Count total zones (leaves)
    var zoneCount: Int {
        switch self {
        case .zone: return 1
        case .split(_, _, let first, let second):
            return first.zoneCount + second.zoneCount
        }
    }

    /// Flatten the tree into (label, rect) pairs given a bounding rect.
    /// Rect is in fractional coordinates (0-1).
    func flattenZones(in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [(label: String, rect: CGRect)] {
        switch self {
        case .zone(let label):
            return [(label: label, rect: rect)]
        case .split(let dir, let ratio, let first, let second):
            let (r1, r2) = splitRect(rect, direction: dir, ratio: ratio)
            return first.flattenZones(in: r1) + second.flattenZones(in: r2)
        }
    }

    /// Split a rect by direction and ratio
    private func splitRect(_ rect: CGRect, direction: SplitDirection, ratio: Double) -> (CGRect, CGRect) {
        let r = CGFloat(ratio)
        switch direction {
        case .vertical:
            let w1 = rect.width * r
            return (
                CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height),
                CGRect(x: rect.minX + w1, y: rect.minY, width: rect.width - w1, height: rect.height)
            )
        case .horizontal:
            let h1 = rect.height * r
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1),
                CGRect(x: rect.minX, y: rect.minY + h1, width: rect.width, height: rect.height - h1)
            )
        }
    }
}

// MARK: - Legacy support (keep old types compiling but unused)

struct KeyComboConfig: Codable {
    var key: String
    var modifiers: [String]
}

// MARK: - Grid layout: row/column tracks + zones spanning any rectangle of cells.
// Replaces the binary split tree so ANY rectangular group of cells can merge —
// e.g. the top half plus the top half of the bottom half.

struct GridZone: Codable, Equatable {
    var label: String
    var r0: Int  // inclusive track ranges
    var r1: Int
    var c0: Int
    var c1: Int
}

struct GridLayout: Codable, Equatable {
    var rows: [Double]   // fractional track sizes, bottom -> top (Cocoa y-up), sum 1
    var cols: [Double]   // left -> right, sum 1
    var zones: [GridZone]

    init(rows: [Double], cols: [Double], zones: [GridZone]) {
        self.rows = rows; self.cols = cols; self.zones = zones
    }

    /// Convert a legacy split tree into a grid (exact same zone rects).
    init(tree: SplitNode) {
        let flat = tree.flattenZones()
        func key(_ v: CGFloat) -> Double { (Double(v) * 100000).rounded() / 100000 }
        var xs: Set<Double> = [0, 1], ys: Set<Double> = [0, 1]
        for z in flat {
            xs.insert(key(z.rect.minX)); xs.insert(key(z.rect.maxX))
            ys.insert(key(z.rect.minY)); ys.insert(key(z.rect.maxY))
        }
        let xe = xs.sorted(), ye = ys.sorted()
        cols = (1..<xe.count).map { xe[$0] - xe[$0 - 1] }
        rows = (1..<ye.count).map { ye[$0] - ye[$0 - 1] }
        func idx(_ edges: [Double], _ v: CGFloat) -> Int {
            let k = key(v)
            return edges.enumerated().min(by: { abs($0.1 - k) < abs($1.1 - k) })!.0
        }
        zones = flat.map { z in
            GridZone(label: z.label,
                     r0: idx(ye, z.rect.minY), r1: idx(ye, z.rect.maxY) - 1,
                     c0: idx(xe, z.rect.minX), c1: idx(xe, z.rect.maxX) - 1)
        }
    }

    // MARK: edges / rects

    func rowEdges() -> [Double] { var a: [Double] = [0]; for r in rows { a.append(a.last! + r) }; return a }
    func colEdges() -> [Double] { var a: [Double] = [0]; for c in cols { a.append(a.last! + c) }; return a }

    /// Fractional rects, same coordinate space the split tree produced.
    func rects() -> [(label: String, rect: CGRect)] {
        let re = rowEdges(), ce = colEdges()
        return zones.map { z in
            (label: z.label, rect: CGRect(
                x: ce[z.c0], y: re[z.r0],
                width: ce[z.c1 + 1] - ce[z.c0],
                height: re[z.r1 + 1] - re[z.r0]))
        }
    }

    // MARK: track insertion

    /// Insert a horizontal boundary at fraction f (0-1). Returns the boundary index.
    mutating func insertRowBoundary(at f: Double) -> Int {
        let edges = rowEdges()
        for (i, e) in edges.enumerated() where abs(e - f) < 0.0005 { return i }
        guard let t = (0..<rows.count).first(where: { edges[$0] < f && f < edges[$0 + 1] }) else { return 0 }
        let lower = f - edges[t], upper = edges[t + 1] - f
        rows[t] = lower
        rows.insert(upper, at: t + 1)
        for i in zones.indices {
            if zones[i].r0 > t { zones[i].r0 += 1 }
            if zones[i].r1 >= t + 1 || (zones[i].r0 <= t && zones[i].r1 >= t) { zones[i].r1 += 1 }
        }
        return t + 1
    }

    mutating func insertColBoundary(at f: Double) -> Int {
        let edges = colEdges()
        for (i, e) in edges.enumerated() where abs(e - f) < 0.0005 { return i }
        guard let t = (0..<cols.count).first(where: { edges[$0] < f && f < edges[$0 + 1] }) else { return 0 }
        let left = f - edges[t], right = edges[t + 1] - f
        cols[t] = left
        cols.insert(right, at: t + 1)
        for i in zones.indices {
            if zones[i].c0 > t { zones[i].c0 += 1 }
            if zones[i].c1 >= t + 1 || (zones[i].c0 <= t && zones[i].c1 >= t) { zones[i].c1 += 1 }
        }
        return t + 1
    }

    // MARK: zone operations

    mutating func splitZone(at index: Int, direction: SplitDirection, parts: Int) {
        guard zones.indices.contains(index), parts >= 2 else { return }
        let label = zones[index].label
        if direction == .horizontal {
            let re = rowEdges()
            let lo = re[zones[index].r0], hi = re[zones[index].r1 + 1]
            var bounds: [Int] = []
            for k in 1..<parts { bounds.append(insertRowBoundary(at: lo + (hi - lo) * Double(k) / Double(parts))) }
            guard let zi = zones.firstIndex(where: { $0.label == label }) else { return }
            let z = zones.remove(at: zi)
            var cuts = [z.r0] + bounds.sorted() + [z.r1 + 1]
            cuts = Array(Set(cuts)).sorted()
            for i in 0..<(cuts.count - 1) {
                zones.append(GridZone(label: "\(z.label).\(i)", r0: cuts[i], r1: cuts[i + 1] - 1, c0: z.c0, c1: z.c1))
            }
        } else {
            let ce = colEdges()
            let lo = ce[zones[index].c0], hi = ce[zones[index].c1 + 1]
            var bounds: [Int] = []
            for k in 1..<parts { bounds.append(insertColBoundary(at: lo + (hi - lo) * Double(k) / Double(parts))) }
            guard let zi = zones.firstIndex(where: { $0.label == label }) else { return }
            let z = zones.remove(at: zi)
            var cuts = [z.c0] + bounds.sorted() + [z.c1 + 1]
            cuts = Array(Set(cuts)).sorted()
            for i in 0..<(cuts.count - 1) {
                zones.append(GridZone(label: "\(z.label).\(i)", r0: z.r0, r1: z.r1, c0: cuts[i], c1: cuts[i + 1] - 1))
            }
        }
        normalize()
    }

    /// Any selection whose cells form a perfect rectangle (with no outside
    /// zone overlapping it) can merge — this is the freedom the tree lacked.
    func canMerge(_ sel: Set<Int>) -> Bool {
        guard sel.count >= 2 else { return false }
        let zs = sel.compactMap { zones.indices.contains($0) ? zones[$0] : nil }
        guard zs.count == sel.count else { return false }
        let r0 = zs.map(\.r0).min()!, r1 = zs.map(\.r1).max()!
        let c0 = zs.map(\.c0).min()!, c1 = zs.map(\.c1).max()!
        let boundCells = (r1 - r0 + 1) * (c1 - c0 + 1)
        let selCells = zs.reduce(0) { $0 + ($1.r1 - $1.r0 + 1) * ($1.c1 - $1.c0 + 1) }
        guard selCells == boundCells else { return false }
        for (i, z) in zones.enumerated() where !sel.contains(i) {
            let overlaps = !(z.r1 < r0 || z.r0 > r1 || z.c1 < c0 || z.c0 > c1)
            if overlaps { return false }
        }
        return true
    }

    mutating func merge(_ sel: Set<Int>) {
        guard canMerge(sel) else { return }
        let zs = sel.map { zones[$0] }
        let merged = GridZone(label: zs.first!.label,
                              r0: zs.map(\.r0).min()!, r1: zs.map(\.r1).max()!,
                              c0: zs.map(\.c0).min()!, c1: zs.map(\.c1).max()!)
        zones = zones.enumerated().filter { !sel.contains($0.0) }.map(\.1)
        zones.append(merged)
        normalize()
    }

    mutating func removeZones(_ sel: Set<Int>) {
        zones = zones.enumerated().filter { !sel.contains($0.0) }.map(\.1)
        normalize()
    }

    /// Create a 1x1 zone in an empty cell.
    mutating func addZone(atRow r: Int, col c: Int) {
        guard zoneIndex(atRow: r, col: c) == nil else { return }
        zones.append(GridZone(label: "+", r0: r, r1: r, c0: c, c1: c))
        normalize()
    }

    func zoneIndex(atRow r: Int, col c: Int) -> Int? {
        zones.firstIndex { r >= $0.r0 && r <= $0.r1 && c >= $0.c0 && c <= $0.c1 }
    }

    func cell(atPoint p: CGPoint) -> (r: Int, c: Int)? {
        let re = rowEdges(), ce = colEdges()
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return nil }
        let r = max(0, min(rows.count - 1, (0..<rows.count).first(where: { Double(p.y) < re[$0 + 1] }) ?? rows.count - 1))
        let c = max(0, min(cols.count - 1, (0..<cols.count).first(where: { Double(p.x) < ce[$0 + 1] }) ?? cols.count - 1))
        return (r, c)
    }

    /// Drop unused boundaries and renumber labels in reading order (top-left first).
    mutating func normalize() {
        var changed = true
        while changed {
            changed = false
            var k = 1
            while k < rows.count {
                let used = zones.contains { $0.r0 == k || $0.r1 == k - 1 }
                if !used {
                    rows[k - 1] += rows[k]
                    rows.remove(at: k)
                    for i in zones.indices {
                        if zones[i].r0 >= k { zones[i].r0 -= 1 }
                        if zones[i].r1 >= k { zones[i].r1 -= 1 }
                    }
                    changed = true
                } else { k += 1 }
            }
            k = 1
            while k < cols.count {
                let used = zones.contains { $0.c0 == k || $0.c1 == k - 1 }
                if !used {
                    cols[k - 1] += cols[k]
                    cols.remove(at: k)
                    for i in zones.indices {
                        if zones[i].c0 >= k { zones[i].c0 -= 1 }
                        if zones[i].c1 >= k { zones[i].c1 -= 1 }
                    }
                    changed = true
                } else { k += 1 }
            }
        }
        // reading order: top row first (high y), then left to right
        zones.sort { a, b in
            if a.r1 != b.r1 { return a.r1 > b.r1 }
            return a.c0 < b.c0
        }
        for (i, _) in zones.enumerated() { zones[i].label = "\(i + 1)" }
    }

    static var defaultHalves: GridLayout {
        GridLayout(rows: [1], cols: [0.5, 0.5], zones: [
            GridZone(label: "1", r0: 0, r1: 0, c0: 0, c1: 0),
            GridZone(label: "2", r0: 0, r1: 0, c0: 1, c1: 1)])
    }
    static var defaultQuad: GridLayout {
        GridLayout(rows: [0.5, 0.5], cols: [0.5, 0.5], zones: [
            GridZone(label: "1", r0: 1, r1: 1, c0: 0, c1: 0),
            GridZone(label: "2", r0: 1, r1: 1, c0: 1, c1: 1),
            GridZone(label: "3", r0: 0, r1: 0, c0: 0, c1: 0),
            GridZone(label: "4", r0: 0, r1: 0, c0: 1, c1: 1)])
    }
}

extension ScreenLayout {
    var effectiveGrid: GridLayout { grid ?? GridLayout(tree: root) }
    var zoneRects: [(label: String, rect: CGRect)] { effectiveGrid.rects() }
}
