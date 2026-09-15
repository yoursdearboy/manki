// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Manki",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "manki-cli", targets: ["MankiCLI"])
    ],
    targets: [
        .executableTarget(name: "MankiCLI", path: "MankiCLI")
    ]
)
