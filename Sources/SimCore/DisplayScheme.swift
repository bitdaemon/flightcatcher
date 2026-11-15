import Foundation

/// Every colour the display uses, as 0xRRGGBB. The app maps these to SwiftUI colours; keeping them here lets tests
/// check that the schemes stay clearly distinguishable.
public struct SchemeColors: Equatable {
    public var background: UInt32
    public var panel: UInt32
    public var panelBorder: UInt32
    public var rowHighlight: UInt32
    public var text: UInt32
    public var dimText: UInt32
    public var heading: UInt32
    public var selected: UInt32
    public var compass: UInt32
    public var compassLabel: UInt32
    public var rings: UInt32
    public var runway: UInt32
    public var runwayCentreline: UInt32
    public var fix: UInt32
    public var star: UInt32
    public var sid: UInt32
    public var approach: UInt32
    public var route: UInt32
    public var aircraft: UInt32
    public var ok: UInt32
    public var warning: UInt32
    public var alert: UInt32
    public var controller: UInt32
    public var pilot: UInt32
    public var system: UInt32
}

public struct DisplayScheme: Identifiable, Equatable {
    public let id: String
    public let name: String
    /// True for light backgrounds; the app switches system controls to the light appearance.
    public let isLight: Bool
    public let colors: SchemeColors
}

/// Colour schemes. Line features on the scope (STARs, SIDs, approaches, the selected aircraft's route, runways) are
/// kept at least a set colour distance apart in every scheme; `DisplaySchemeTests` enforces it.
public enum DisplaySchemes {
    public static let defaultID = "slate"

    public static func scheme(id: String) -> DisplayScheme {
        all.first { $0.id == id } ?? all[0]
    }

    public static let all: [DisplayScheme] = [
        DisplayScheme(id: "slate", name: "Slate", isLight: false, colors: SchemeColors(
                background: 0x1B2430, panel: 0x252F3D, panelBorder: 0x3F4E63, rowHighlight: 0x34445A, text: 0xE6EAF0,
                dimText: 0x8D9BAE, heading: 0x6CB6FF, selected: 0xFFE14D, compass: 0x8D9BAE, compassLabel: 0xB4C0D0,
                rings: 0x2F3E52, runway: 0xCDD5E0, runwayCentreline: 0x6C7A8E, fix: 0x8D9BAE, star: 0x35D0BA,
                sid: 0xB28DFF, approach: 0xFF6EB4, route: 0xFF9338, aircraft: 0xFFFFFF, ok: 0x6FCF97,
                warning: 0xF5A524, alert: 0xFF5A5F, controller: 0x6CB6FF, pilot: 0xE6EAF0, system: 0x8D9BAE)),
        DisplayScheme(id: "midnight", name: "Midnight", isLight: false, colors: SchemeColors(
                background: 0x0B1020, panel: 0x141B33, panelBorder: 0x2A3560, rowHighlight: 0x1F2A4D, text: 0xE8ECFF,
                dimText: 0x8791C0, heading: 0x7AA2FF, selected: 0xFFE14D, compass: 0x7C86B8, compassLabel: 0xA9B3E0,
                rings: 0x1C2547, runway: 0xA8B6EE, runwayCentreline: 0x5A6699, fix: 0x7C86B8, star: 0x2EE6A6,
                sid: 0xC77DFF, approach: 0xFF5FA2, route: 0xFF8A3D, aircraft: 0xFFFFFF, ok: 0x5BE49B,
                warning: 0xFFB020, alert: 0xFF4D5E, controller: 0x7AA2FF, pilot: 0xE8ECFF, system: 0x8791C0)),
        DisplayScheme(id: "graphite", name: "Graphite", isLight: false, colors: SchemeColors(
                background: 0x17191C, panel: 0x22262B, panelBorder: 0x3B4148, rowHighlight: 0x2E343B, text: 0xECEFF2,
                dimText: 0x9AA2AB, heading: 0x8AB4F8, selected: 0xFFE14D, compass: 0x8B939C, compassLabel: 0xB8BFC7,
                rings: 0x2A2E33, runway: 0xC2C8CF, runwayCentreline: 0x6A727B, fix: 0x8B939C, star: 0x4DD0C4,
                sid: 0xBA9BFF, approach: 0xFF7EB6, route: 0xFF9338, aircraft: 0xFFFFFF, ok: 0x7BD88F,
                warning: 0xFFB300, alert: 0xFF6B6B, controller: 0x8AB4F8, pilot: 0xECEFF2, system: 0x9AA2AB)),
        DisplayScheme(id: "phosphor", name: "Phosphor", isLight: false, colors: SchemeColors(
                background: 0x04110A, panel: 0x0A1E12, panelBorder: 0x1B4A2C, rowHighlight: 0x123222, text: 0xC8FFD8,
                dimText: 0x6FAE85, heading: 0x5CFF9A, selected: 0xFFF066, compass: 0x3FA866, compassLabel: 0x8FE8B0,
                rings: 0x0D2A18, runway: 0xB8E8C8, runwayCentreline: 0x3C7A55, fix: 0x4F9A6C, star: 0x3DDCFF,
                sid: 0xC58CFF, approach: 0xFF6FB5, route: 0xFF9640, aircraft: 0xFFFFFF, ok: 0x5CFF9A,
                warning: 0xFFC400, alert: 0xFF4D4D, controller: 0x5CFF9A, pilot: 0xC8FFD8, system: 0x6FAE85)),
        DisplayScheme(id: "amber", name: "Amber", isLight: false, colors: SchemeColors(
                background: 0x120A00, panel: 0x1E1405, panelBorder: 0x4A3410, rowHighlight: 0x33230A, text: 0xFFE3B0,
                dimText: 0xB08A4A, heading: 0xFFB84D, selected: 0xFFE14D, compass: 0xA37A33, compassLabel: 0xD9B26A,
                rings: 0x2A1C08, runway: 0xE6D2A8, runwayCentreline: 0x7A5A25, fix: 0x9C7B40, star: 0x45D9E8,
                sid: 0xB794FF, approach: 0xFF6FA8, route: 0x7DFF9B, aircraft: 0xFFFFFF, ok: 0x7DFF9B,
                warning: 0xFF9F1C, alert: 0xFF4D4D, controller: 0xFFB84D, pilot: 0xFFE3B0, system: 0xB08A4A)),
        DisplayScheme(id: "daylight", name: "Daylight", isLight: true, colors: SchemeColors(
                background: 0xF4F6F9, panel: 0xFFFFFF, panelBorder: 0xC3CBD6, rowHighlight: 0xE3E9F1, text: 0x1B2430,
                dimText: 0x5C6B7E, heading: 0x0B63CE, selected: 0x8A00D4, compass: 0x7C8A9C, compassLabel: 0x4A5868,
                rings: 0xDDE3EB, runway: 0x39465A, runwayCentreline: 0x8A97A8, fix: 0x6B7B8E, star: 0x00897B,
                sid: 0x3D5AFE, approach: 0xD6007A, route: 0xE65100, aircraft: 0x0A0F1A, ok: 0x1B8A4B,
                warning: 0xB26A00, alert: 0xD32F2F, controller: 0x0B63CE, pilot: 0x1B2430, system: 0x5C6B7E)),
        DisplayScheme(id: "paper", name: "Paper", isLight: true, colors: SchemeColors(
                background: 0xF3ECDD, panel: 0xFBF7EE, panelBorder: 0xCDBF9F, rowHighlight: 0xE8DDC4, text: 0x2B2218,
                dimText: 0x7A6A52, heading: 0x1F5FA8, selected: 0x8A00D4, compass: 0x8C7B5E, compassLabel: 0x5A4A32,
                rings: 0xE2D7BC, runway: 0x3A2F20, runwayCentreline: 0x9A8A6C, fix: 0x7A6A52, star: 0x00796B,
                sid: 0x3D5AFE, approach: 0xC2185B, route: 0xE65100, aircraft: 0x120D06, ok: 0x2E7D32,
                warning: 0xA86400, alert: 0xC62828, controller: 0x1F5FA8, pilot: 0x2B2218, system: 0x7A6A52)),
        DisplayScheme(id: "high-contrast", name: "High contrast", isLight: false, colors: SchemeColors(
                background: 0x000000, panel: 0x0D0D0D, panelBorder: 0x8C8C8C, rowHighlight: 0x2B2B2B, text: 0xFFFFFF,
                dimText: 0xBFBFBF, heading: 0x00E5FF, selected: 0xFFEB3B, compass: 0xA6A6A6, compassLabel: 0xE6E6E6,
                rings: 0x262626, runway: 0xC9C9C9, runwayCentreline: 0x808080, fix: 0xA6A6A6, star: 0x00E58F,
                sid: 0xB388FF, approach: 0xFF4081, route: 0xFF9100, aircraft: 0xFFFFFF, ok: 0x00E676,
                warning: 0xFFC400, alert: 0xFF1744, controller: 0x00E5FF, pilot: 0xFFFFFF, system: 0xBFBFBF)),
        DisplayScheme(id: "colour-blind-safe", name: "Colour-blind safe", isLight: false, colors: SchemeColors(
                background: 0x14181F, panel: 0x1F2530, panelBorder: 0x3C4658, rowHighlight: 0x2B3342, text: 0xF0F2F5,
                dimText: 0x9AA5B5, heading: 0x56B4E9, selected: 0xF0E442, compass: 0x8794A8, compassLabel: 0xB9C3D1,
                rings: 0x232A36, runway: 0xB4BAC3, runwayCentreline: 0x667284, fix: 0x8794A8, star: 0x56B4E9,
                sid: 0xCC79A7, approach: 0x009E73, route: 0xFFFFFF, aircraft: 0xFFFFFF, ok: 0x009E73,
                warning: 0xE69F00, alert: 0xD55E00, controller: 0x56B4E9, pilot: 0xF0F2F5, system: 0x9AA5B5)),
        DisplayScheme(id: "solar-dark", name: "Solar dark", isLight: false, colors: SchemeColors(
                background: 0x002B36, panel: 0x073642, panelBorder: 0x586E75, rowHighlight: 0x0F4552, text: 0xEEE8D5,
                dimText: 0x93A1A1, heading: 0x3AA0E8, selected: 0xFFD84A, compass: 0x7B9096, compassLabel: 0xA9B8B8,
                rings: 0x0B3B47, runway: 0xC9D2C6, runwayCentreline: 0x62797F, fix: 0x7B9096, star: 0x2AA198,
                sid: 0x8C90E8, approach: 0xE04C96, route: 0xF07A3A, aircraft: 0xFDF6E3, ok: 0x9BB800,
                warning: 0xE0A100, alert: 0xF0534F, controller: 0x3AA0E8, pilot: 0xEEE8D5, system: 0x93A1A1)),
        DisplayScheme(id: "nord", name: "Nord", isLight: false, colors: SchemeColors(
                background: 0x2E3440, panel: 0x3B4252, panelBorder: 0x4C566A, rowHighlight: 0x434C5E, text: 0xECEFF4,
                dimText: 0x9FAABD, heading: 0x88C0D0, selected: 0xFFE08A, compass: 0x8A96AB, compassLabel: 0xB7C1D3,
                rings: 0x3A4152, runway: 0xC4CCDA, runwayCentreline: 0x6B7790, fix: 0x8A96AB, star: 0x7BE0B4,
                sid: 0xB48EF0, approach: 0xFF7FA8, route: 0xFF9A52, aircraft: 0xFFFFFF, ok: 0xA3D68C,
                warning: 0xEBB04B, alert: 0xFF6B72, controller: 0x88C0D0, pilot: 0xECEFF4, system: 0x9FAABD)),
        DisplayScheme(id: "dracula", name: "Dracula", isLight: false, colors: SchemeColors(
                background: 0x282A36, panel: 0x343746, panelBorder: 0x4F5370, rowHighlight: 0x3E4155, text: 0xF8F8F2,
                dimText: 0xA0A6C6, heading: 0x8BE9FD, selected: 0xF1FA8C, compass: 0x8E94B4, compassLabel: 0xBDC2DC,
                rings: 0x32354A, runway: 0xC8CCE0, runwayCentreline: 0x6D7396, fix: 0x8E94B4, star: 0x50FA7B,
                sid: 0xBD93F9, approach: 0xFF79C6, route: 0xFFA04D, aircraft: 0xFFFFFF, ok: 0x50FA7B,
                warning: 0xF1C232, alert: 0xFF5555, controller: 0x8BE9FD, pilot: 0xF8F8F2, system: 0xA0A6C6)),
        DisplayScheme(id: "ocean", name: "Ocean", isLight: false, colors: SchemeColors(
                background: 0x06232B, panel: 0x0C3440, panelBorder: 0x1F5B6B, rowHighlight: 0x124452, text: 0xE2F6FA,
                dimText: 0x7FB0BC, heading: 0x5CC8FF, selected: 0xFFE14D, compass: 0x5E9AA8, compassLabel: 0x9BCBD6,
                rings: 0x0E3B48, runway: 0xA9D2DC, runwayCentreline: 0x4C8594, fix: 0x5E9AA8, star: 0x6BF0A8,
                sid: 0xC49BFF, approach: 0xFF6FA8, route: 0xFF8F3E, aircraft: 0xFFFFFF, ok: 0x6BF0A8,
                warning: 0xFFB52E, alert: 0xFF5A6A, controller: 0x5CC8FF, pilot: 0xE2F6FA, system: 0x7FB0BC)),
        DisplayScheme(id: "dusk", name: "Dusk", isLight: false, colors: SchemeColors(
                background: 0x1E1530, panel: 0x2A1F40, panelBorder: 0x4C3C73, rowHighlight: 0x382A55, text: 0xF1EAFF,
                dimText: 0xA99BC9, heading: 0x9CB5FF, selected: 0xFFE14D, compass: 0x8F82B3, compassLabel: 0xC3B8DE,
                rings: 0x2D2245, runway: 0xC9BFE6, runwayCentreline: 0x6C5F94, fix: 0x8F82B3, star: 0x4DE0C0,
                sid: 0xA98BFF, approach: 0xFF6CB0, route: 0xFF9140, aircraft: 0xFFFFFF, ok: 0x6FE3A0,
                warning: 0xFFB92E, alert: 0xFF5A66, controller: 0x9CB5FF, pilot: 0xF1EAFF, system: 0xA99BC9)),
    ]
}
