import SwiftUI

/// Text size of the whole app, from 60% to 180%, saved between runs. Fonts go through `Font.ui(size:)`, which applies the
/// factor, and the few layout values that follow the text (tag boxes, panel widths) multiply by it too.
enum UIScale {
    static let key = "uiScale"
    static let range: ClosedRange<CGFloat> = 0.6...1.8
    static let steps: [CGFloat] = [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]
    nonisolated(unsafe) static var factor: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: key)
        return saved == 0 ? 1 : min(max(CGFloat(saved), 0.6), 1.8)
    }()
}

/// Changes the factor and tells the views to redraw.
@MainActor
final class UIScaleStore: ObservableObject {
    static let shared = UIScaleStore()
    @Published private(set) var factor: CGFloat = UIScale.factor

    var percent: Int { Int((factor * 100).rounded()) }

    func set(_ value: CGFloat) {
        let v = min(max(value, UIScale.range.lowerBound), UIScale.range.upperBound)
        UIScale.factor = v
        factor = v
        UserDefaults.standard.set(Double(v), forKey: UIScale.key)
    }

    func larger() { if let next = UIScale.steps.first(where: { $0 > factor + 0.001 }) { set(next) } }
    func smaller() { if let next = UIScale.steps.last(where: { $0 < factor - 0.001 }) { set(next) } }
    func reset() { set(1) }
}

extension Font {
    /// Like `Font.system(size:weight:design:)`, multiplied by the text-size setting.
    static func ui(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * UIScale.factor, weight: weight, design: design)
    }
}
