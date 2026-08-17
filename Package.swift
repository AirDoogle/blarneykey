// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BlarneyKey",
    platforms: [.macOS(.v15)],
    targets: [
        // No external dependencies on purpose: this builds with no network access.
        .executableTarget(
            name: "BlarneyKey",
            path: "Sources/BlarneyKey",
            // AppKit and SwiftUI callbacks here are all main-thread by construction;
            // Swift 6's strict checking has no way to see that, so stay on v5 mode.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
