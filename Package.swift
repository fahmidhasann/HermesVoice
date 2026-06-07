// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HermesVoice",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure, hardware-free logic shared by the app and exercised by tests.
        .target(
            name: "HermesVoiceKit",
            path: "Sources/HermesVoiceKit"
        ),
        .executableTarget(
            name: "HermesVoice",
            dependencies: ["HermesVoiceKit"],
            path: "Sources/HermesVoice",
            resources: [
                .copy("../../Resources/Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SwiftUI")
            ]
        ),
        // Standalone test runner. XCTest/swift-testing aren't available under
        // the Command Line Tools toolchain (no full Xcode), so the suite is a
        // plain executable with a tiny assert harness — run with
        // `swift run HermesVoiceTests`.
        .executableTarget(
            name: "HermesVoiceTests",
            dependencies: ["HermesVoiceKit"],
            path: "Tests/HermesVoiceTests"
        )
    ]
)
