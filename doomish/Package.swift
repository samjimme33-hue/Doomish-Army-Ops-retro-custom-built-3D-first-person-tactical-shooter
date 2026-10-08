// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Doomish",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "Doomish",
            path: "Sources/Doomish",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
