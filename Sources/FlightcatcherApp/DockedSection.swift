import SwiftUI
import AppKit

/// A panel fixed in a side column of the docked layout: a small upper-case header and its content, separated from
/// the next section by a hairline. Uses the current colour scheme, so it works with every scheme.
struct DockedSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    /// Hides the section (from the panel buttons in the control bar).
    var onClose: (() -> Void)? = nil
    /// Take all the height on offer (false: only as tall as the content).
    var fills = true
    @ViewBuilder var content: () -> Content
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.ui(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(theme.dimText)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.ui(size: 10, design: .monospaced))
                        .foregroundStyle(theme.dimText)
                }
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.ui(size: 9)).foregroundStyle(theme.dimText)
                    }
                    .buttonStyle(.plain)
                    .help("Hide (bring back with its button in the control bar)")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26 * UIScale.factor)
            if fills {
                content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                content().frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.panelBorder).frame(height: 1) }
    }
}

/// A thin strip that resizes a docked column or section when dragged, with the matching resize cursor.
struct DockResizeHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    /// Called with the drag distance since the drag began (points, right or down positive), and nil when it ends.
    let onDrag: (CGFloat?) -> Void
    @State private var hovering = false
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Rectangle()
            .fill(hovering ? themeStore.theme.heading.opacity(0.5) : Color.clear)
            .frame(width: axis == .horizontal ? 5 : nil, height: axis == .vertical ? 5 : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onDrag(axis == .horizontal ? $0.translation.width : $0.translation.height) }
                    .onEnded { _ in onDrag(nil) }
            )
            .help("Drag to resize")
    }
}
