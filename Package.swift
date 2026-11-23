// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lotse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lotse",
            path: "Sources/Lotse",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
