// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MinimaStudio",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MinimaStudio",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            path: "Sources/MinimaStudio"
        ),
        // Captures de mise en page (dépôt de vérification uniquement, pas dans l'app livrée).
        .testTarget(
            name: "SnapshotTests",
            dependencies: ["MinimaStudio"],
            path: "Tests/SnapshotTests"
        )
    ]
)
