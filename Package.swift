// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Boto",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KanbanCore"),
        .target(name: "KanbanUI", dependencies: ["KanbanCore"]),
        .executableTarget(name: "Boto", dependencies: ["KanbanUI", "KanbanCore"]),
        .testTarget(name: "KanbanCoreTests", dependencies: ["KanbanCore"]),
        .testTarget(name: "KanbanUITests", dependencies: ["KanbanUI", "KanbanCore"]),    ]
)
