// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "DueBadgeCore", targets: ["DueBadgeCore"])
]
var targets: [Target] = [
    .target(
        name: "DueBadgeCore",
        path: "Manki",
        exclude: ["AnkiRSLibBackend.swift", "AppIconBadgeController.swift", "Assets.xcassets", "ContentView.swift", "MankiApp.swift", "NotificationRouter.swift", "NotificationSettings.swift", "RSLibViewModel.swift"],
        sources: ["DueBadgeCount.swift", "ReviewCardSettings.swift", "StudySettings.swift"]
    ),
    .testTarget(name: "DueBadgeCoreTests", dependencies: ["DueBadgeCore"])
]

let package = Package(
    name: "Manki",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
