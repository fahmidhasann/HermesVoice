// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HermesVoice",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // GitHub-flavored markdown rendering for assistant messages.
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", exact: "2.4.1"),
        // Syntax highlighting for fenced code blocks (wraps highlight.js).
        .package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0")
    ],
    targets: [
        // Pure, hardware-free logic shared by the app and exercised by tests.
        .target(
            name: "HermesVoiceKit",
            path: "Sources/HermesVoiceKit"
        ),
        .executableTarget(
            name: "HermesVoice",
            dependencies: [
                "HermesVoiceKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr")
            ],
            path: "Sources/HermesVoice",
            resources: [
                .copy("../../Resources/Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security")
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
