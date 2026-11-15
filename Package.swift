// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flightcatcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimCore", targets: ["SimCore"]),
        .executable(name: "FlightcatcherApp", targets: ["FlightcatcherApp"]),
    ],
    targets: [
        // UI-free simulation engine and airport package model.
        .target(
            name: "SimCore",
            resources: [.copy("Resources")]
        ),
        // SwiftUI radar scope. Run this scheme from Xcode (Cmd+R).
        .executableTarget(
            name: "FlightcatcherApp",
            dependencies: ["SimCore"]
        ),
        .testTarget(
            name: "SimCoreTests",
            dependencies: ["SimCore"]
        ),
    ]
)
