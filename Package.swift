// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cleanmac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CleanMacCore"),
        .executableTarget(name: "cleanmac", dependencies: ["CleanMacCore"]),
        .executableTarget(name: "CleanMacBar", dependencies: ["CleanMacCore"]),
    ]
)
