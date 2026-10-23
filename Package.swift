// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Miras",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Miras", targets: ["Miras"])],
    targets: [
        .target(name: "MirasCore"),
        .executableTarget(name: "Miras", dependencies: ["MirasCore"]),
        .testTarget(name: "MirasCoreTests", dependencies: ["MirasCore"])
    ]
)
