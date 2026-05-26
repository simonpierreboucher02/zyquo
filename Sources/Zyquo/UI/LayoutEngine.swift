import Foundation

public enum LayoutChild: Sendable {
    case fixed(Int)
    case grow(Double)
    case shrink(min: Int)

    var minSize: Int {
        switch self {
        case .fixed(let s): return s
        case .grow: return 0
        case .shrink(let m): return m
        }
    }
}

public struct LayoutConstraint: Sendable {
    public let sizing: LayoutChild
    public let minSize: Int?
    public let maxSize: Int?

    public init(_ sizing: LayoutChild, min: Int? = nil, max: Int? = nil) {
        self.sizing = sizing
        self.minSize = min
        self.maxSize = max
    }
}

public enum LayoutDirection: Sendable {
    case row
    case column
}

public struct LayoutEngine: Sendable {
    public init() {}

    public func compute(direction: LayoutDirection, available: Region, children: [LayoutConstraint]) -> [Region] {
        guard !children.isEmpty else { return [] }

        let total: Int
        switch direction {
        case .row: total = available.width
        case .column: total = available.height
        }

        let sizes = allocate(total: total, constraints: children)
        var regions: [Region] = []
        var offset = 0

        for (i, size) in sizes.enumerated() {
            let _ = i
            switch direction {
            case .row:
                regions.append(Region(x: available.x + offset, y: available.y, width: size, height: available.height))
            case .column:
                regions.append(Region(x: available.x, y: available.y + offset, width: available.width, height: size))
            }
            offset += size
        }

        return regions
    }

    private func allocate(total: Int, constraints: [LayoutConstraint]) -> [Int] {
        var sizes = Array(repeating: 0, count: constraints.count)

        var fixedUsed = 0
        var totalGrow = 0.0

        for (i, c) in constraints.enumerated() {
            switch c.sizing {
            case .fixed(let s):
                let clamped = clamp(s, min: c.minSize, max: c.maxSize)
                sizes[i] = clamped
                fixedUsed += clamped
            case .shrink(let m):
                sizes[i] = m
                fixedUsed += m
            case .grow(let weight):
                totalGrow += weight
            }
        }

        let remaining = max(0, total - fixedUsed)

        if totalGrow > 0 {
            var growRemaining = remaining
            for (i, c) in constraints.enumerated() {
                if case .grow(let weight) = c.sizing {
                    let share = Int(Double(remaining) * weight / totalGrow)
                    let clamped = clamp(share, min: c.minSize, max: c.maxSize)
                    sizes[i] = clamped
                    growRemaining -= clamped
                }
            }

            if growRemaining > 0 {
                for (i, c) in constraints.enumerated() {
                    if case .grow = c.sizing {
                        let maxAllowed = c.maxSize ?? Int.max
                        let canAdd = maxAllowed - sizes[i]
                        if canAdd > 0 {
                            let add = min(canAdd, growRemaining)
                            sizes[i] += add
                            growRemaining -= add
                            if growRemaining <= 0 { break }
                        }
                    }
                }
            }
        }

        return sizes
    }

    private func clamp(_ value: Int, min minVal: Int?, max maxVal: Int?) -> Int {
        var v = value
        if let m = minVal { v = max(v, m) }
        if let m = maxVal { v = min(v, m) }
        return v
    }
}
