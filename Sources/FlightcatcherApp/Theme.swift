import SwiftUI
import SimCore

/// SwiftUI colours for the selected colour scheme. The colour values live in SimCore's `DisplaySchemes`.
struct Theme {
    var background: Color
    var panel: Color
    var panelBorder: Color
    var rowHighlight: Color
    var text: Color
    var dimText: Color
    var heading: Color
    var selected: Color
    var compass: Color
    var compassLabel: Color
    var rings: Color
    var runway: Color
    var runwayCentreline: Color
    var fix: Color
    var star: Color
    var sid: Color
    var approach: Color
    var route: Color
    var aircraft: Color
    var ok: Color
    var warning: Color
    var alert: Color
    var controller: Color
    var pilot: Color
    var system: Color

    init(_ c: SchemeColors) {
        background = Color(hex: c.background)
        panel = Color(hex: c.panel)
        panelBorder = Color(hex: c.panelBorder)
        rowHighlight = Color(hex: c.rowHighlight)
        text = Color(hex: c.text)
        dimText = Color(hex: c.dimText)
        heading = Color(hex: c.heading)
        selected = Color(hex: c.selected)
        compass = Color(hex: c.compass)
        compassLabel = Color(hex: c.compassLabel)
        rings = Color(hex: c.rings)
        runway = Color(hex: c.runway)
        runwayCentreline = Color(hex: c.runwayCentreline)
        fix = Color(hex: c.fix)
        star = Color(hex: c.star)
        sid = Color(hex: c.sid)
        approach = Color(hex: c.approach)
        route = Color(hex: c.route)
        aircraft = Color(hex: c.aircraft)
        ok = Color(hex: c.ok)
        warning = Color(hex: c.warning)
        alert = Color(hex: c.alert)
        controller = Color(hex: c.controller)
        pilot = Color(hex: c.pilot)
        system = Color(hex: c.system)
    }
}

/// The selected colour scheme, saved between runs. Views observe it, so changing the scheme redraws everything.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "colorScheme"

    @Published var schemeID: String {
        didSet {
            UserDefaults.standard.set(schemeID, forKey: Self.key)
            apply()
        }
    }
    @Published private(set) var theme: Theme
    @Published private(set) var isLight = false

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? DisplaySchemes.defaultID
        let scheme = DisplaySchemes.scheme(id: saved)
        schemeID = scheme.id
        theme = Theme(scheme.colors)
        isLight = scheme.isLight
    }

    private func apply() {
        let scheme = DisplaySchemes.scheme(id: schemeID)
        theme = Theme(scheme.colors)
        isLight = scheme.isLight
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
