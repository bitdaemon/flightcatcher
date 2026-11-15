// swift-tools-version:5.9
import PackageDescription

// Standalone probe: checks that Apple's on-device model works on this Mac and how it handles ATC phraseology.
let package = Package(
    name: "FMProbe",
    platforms: [.macOS("26.0")],
    targets: [.executableTarget(name: "FMProbe")]
)
