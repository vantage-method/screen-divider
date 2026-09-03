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
}

struct ScreenLayout: Codable {
    var screenName: String  // e.g. "Built-in Retina Display", "default"
    var root: SplitNode
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

    /// Count total leaf cells (tree leaves), regardless of merging.
    var zoneCount: Int {
        switch self {
        case .zone: return 1
        case .split(_, _, let first, let second):
            return first.zoneCount + second.zoneCount
        }
    }

    /// Number of distinct snap zones after merging (leaves sharing a label
    /// count once). This is what the user perceives as "zones".
    var mergedZoneCount: Int {
        var labels = Set<String>()
        for leaf in rawLeaves() { labels.insert(leaf.label) }
        return labels.count
    }

    /// Raw per-leaf rects, one entry per tree leaf (merges NOT applied).
    /// Rect is in fractional coordinates (0-1).
    func rawLeaves(in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [(label: String, rect: CGRect)] {
        switch self {
        case .zone(let label):
            return [(label: label, rect: rect)]
        case .split(let dir, let ratio, let first, let second):
            let (r1, r2) = splitRect(rect, direction: dir, ratio: ratio)
            return first.rawLeaves(in: r1) + second.rawLeaves(in: r2)
        }
    }

    /// Flatten into snap zones. Leaves that share a label are one merged zone,
    /// returned as the union (bounding rect) of their cells. Order follows each
    /// label's first appearance in the tree. Rect is fractional (0-1).
    ///
    /// A merge is only ever created (in the editor) when the selected cells
    /// tile a solid rectangle, so the bounding rect equals the covered area.
    func flattenZones(in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [(label: String, rect: CGRect)] {
        var order: [String] = []
        var union: [String: CGRect] = [:]
        for leaf in rawLeaves(in: rect) {
            if let existing = union[leaf.label] {
                union[leaf.label] = existing.union(leaf.rect)
            } else {
                union[leaf.label] = leaf.rect
                order.append(leaf.label)
            }
        }
        return order.map { (label: $0, rect: union[$0]!) }
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
