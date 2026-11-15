import SwiftUI
import SimCore

/// A package-built executable starts as a background process; make it a normal foreground app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FlightcatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runner = SimRunner(seed: 1)
    @StateObject private var layout = PanelLayout()
    @StateObject private var tags = TagModel()

    init() {
        // Set as early as possible: a package-built executable starts as a background process.
        NSApplication.shared.setActivationPolicy(.regular)
        print("flightcATCher: launching")
    }

    var body: some Scene {
        WindowGroup("flightcATCher") {
            ContentView(runner: runner, layout: layout, tags: tags)
        }
        .defaultSize(width: 1000, height: 800)
        Settings {
            SettingsView(runner: runner, layout: layout, tags: tags)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Larger Text") { UIScaleStore.shared.larger() }.keyboardShortcut("=", modifiers: .command)
                Button("Smaller Text") { UIScaleStore.shared.smaller() }.keyboardShortcut("-", modifiers: .command)
                Button("Default Text Size") { UIScaleStore.shared.reset() }.keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

