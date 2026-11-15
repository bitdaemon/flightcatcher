import Foundation
import CoreGraphics

/// A track tag (the box with callsign, speed and altitude) waiting to be placed next to its aircraft symbol.
public struct TagItem: Equatable {
    public var callsign: String
    /// Screen position of the aircraft symbol.
    public var symbol: CGPoint
    public var size: CGSize
    public init(callsign: String, symbol: CGPoint, size: CGSize) {
        self.callsign = callsign
        self.symbol = symbol
        self.size = size
    }
}

/// Placement of track tags so the boxes do not overlap each other or other aircraft symbols. Pure geometry, no UI.
/// An offset is where the box's top-left corner lies relative to the aircraft symbol, in screen points.
public enum TagPlacement {
    public static let defaultOffset = CGPoint(x: 10, y: -18)
    /// Half-size of the square kept clear around every aircraft symbol.
    static let symbolRadius: CGFloat = 7
    static let margin: CGFloat = 2

    /// Box size for the text lines of a tag (monospaced text).
    public static func size(lines: [String], charWidth: CGFloat = 6.7, lineHeight: CGFloat = 13, padding: CGFloat = 5) -> CGSize {
        let longest = lines.map(\.count).max() ?? 0
        return CGSize(width: CGFloat(longest) * charWidth + padding * 2,
                      height: CGFloat(lines.count) * lineHeight + 6)
    }

    public static func rect(for item: TagItem, offset: CGPoint) -> CGRect {
        CGRect(x: item.symbol.x + offset.x, y: item.symbol.y + offset.y, width: item.size.width, height: item.size.height)
    }

    /// Positions to try, nearest first. The first is the default position.
    public static func candidates(for size: CGSize) -> [CGPoint] {
        let w = size.width, h = size.height
        return [
            defaultOffset,
            CGPoint(x: 10, y: 6), CGPoint(x: -w - 10, y: -h - 4), CGPoint(x: -w - 10, y: 6),
            CGPoint(x: 10, y: -h / 2), CGPoint(x: -w - 10, y: -h / 2),
            CGPoint(x: -w / 2, y: -h - 12), CGPoint(x: -w / 2, y: 12),
            CGPoint(x: 30, y: -h - 24), CGPoint(x: 30, y: 20), CGPoint(x: -w - 30, y: -h - 24), CGPoint(x: -w - 30, y: 20),
            CGPoint(x: -w / 2, y: -h - 30), CGPoint(x: -w / 2, y: 30),
            CGPoint(x: 50, y: -h / 2), CGPoint(x: -w - 50, y: -h / 2),
            CGPoint(x: 55, y: -h - 40), CGPoint(x: 55, y: 36), CGPoint(x: -w - 55, y: -h - 40), CGPoint(x: -w - 55, y: 36),
        ]
    }

    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    /// Chooses offsets for every item not in `fixed`. Items in `fixed` keep their offset from `offsets` (or the default)
    /// and are treated as obstacles. With `keepIfClear`, an item stays where it is whenever that spot is free, so tags
    /// do not jump around from tick to tick. Returns offsets for the non-fixed items only.
    public static func place(items: [TagItem], offsets: [String: CGPoint], fixed: Set<String>,
                             keepIfClear: Bool) -> [String: CGPoint] {
        var placed: [CGRect] = []
        for item in items where fixed.contains(item.callsign) {
            placed.append(rect(for: item, offset: offsets[item.callsign] ?? defaultOffset))
        }
        func symbolSquares(except callsign: String) -> [CGRect] {
            items.filter { $0.callsign != callsign }.map {
                CGRect(x: $0.symbol.x - symbolRadius, y: $0.symbol.y - symbolRadius,
                       width: symbolRadius * 2, height: symbolRadius * 2)
            }
        }
        func cost(_ r: CGRect, obstacles: [CGRect]) -> CGFloat {
            let grown = r.insetBy(dx: -margin, dy: -margin)
            return (placed + obstacles).reduce(0) { $0 + overlapArea(grown, $1) }
        }

        var result: [String: CGPoint] = [:]
        for item in items.sorted(by: { $0.callsign < $1.callsign }) where !fixed.contains(item.callsign) {
            let obstacles = symbolSquares(except: item.callsign)
            var chosen = offsets[item.callsign] ?? defaultOffset
            let currentCost = cost(rect(for: item, offset: chosen), obstacles: obstacles)
            if keepIfClear && currentCost == 0 {
                // stay put
            } else {
                var best = (offset: defaultOffset, cost: CGFloat.infinity)
                for candidate in candidates(for: item.size) {
                    let c = cost(rect(for: item, offset: candidate), obstacles: obstacles)
                    if c < best.cost { best = (candidate, c) }
                    if c == 0 { break }
                }
                // If nothing is clear, a nearly clear current position beats jumping.
                chosen = (keepIfClear && currentCost <= best.cost) ? chosen : best.offset
            }
            result[item.callsign] = chosen
            placed.append(rect(for: item, offset: chosen))
        }
        return result
    }
}
