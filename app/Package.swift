// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "E3372Modem",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "E3372Modem", path: "Sources/E3372Modem")
    ]
)
