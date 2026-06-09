// swift-tools-version:5.9
import PackageDescription

// Lucerne — a ClarisWorks-style word editor for the Mac (Avenue A: native
// AppKit + TextKit exclusion paths). See lucerne-plan.md for the full design.
//
// The package is split into a thin executable (`Lucerne`) that only builds the
// NSApplication and menu, and a library (`LucerneKit`) that holds the model,
// layout engine, views, and file IO so the bulk of the code is unit-testable.
let package = Package(
    name: "Lucerne",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Lucerne", targets: ["Lucerne"]),
        .library(name: "LucerneKit", targets: ["LucerneKit"])
    ],
    targets: [
        .executableTarget(
            name: "Lucerne",
            dependencies: ["LucerneKit"],
            path: "Sources/Lucerne"
        ),
        .target(
            name: "LucerneKit",
            dependencies: [],
            path: "Sources/LucerneKit"
        ),
        .testTarget(
            name: "LucerneKitTests",
            dependencies: ["LucerneKit"],
            path: "Tests/LucerneKitTests"
        )
    ]
)
