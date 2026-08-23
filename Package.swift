// swift-tools-version:5.9
import PackageDescription

// Lucerne — a ClarisWorks-style word editor for the Mac (Avenue A: native
// AppKit + TextKit exclusion paths). See lucerne-plan.md for the full design.
//
// The package is split three ways (docs/ubuntu-port.md Phase 0):
//   • `LucerneCore` — the portable heart: canonical model, `.luce` archive IO,
//     Markdown export, history pruning, style library, page/exclusion geometry.
//     Foundation-only; builds and tests on macOS *and* Linux. This is the
//     reference `.luce` reader/writer any port links or conforms to.
//   • `LucerneKit` (macOS) — AppKit/TextKit views, layout, document plumbing.
//   • `Lucerne` (macOS) — the thin NSApplication executable.
//
// On non-macOS hosts only the core (and its tests) exist, so `swift test` on an
// Ubuntu CI runner exercises the format-conformance suite without AppKit.
// `CZlib` supplies raw-DEFLATE inflate on Linux, where Apple's Compression
// framework is unavailable (macOS keeps using Compression; the system zlib
// module map resolves against the SDK there and is simply unused).

var products: [Product] = [
    .library(name: "LucerneCore", targets: ["LucerneCore"])
]

var targets: [Target] = [
    .systemLibrary(
        name: "CZlib",
        path: "Sources/CZlib",
        providers: [.apt(["zlib1g-dev"])]
    ),
    .target(
        name: "LucerneCore",
        dependencies: ["CZlib"],
        path: "Sources/LucerneCore"
    ),
    .testTarget(
        name: "LucerneCoreTests",
        dependencies: ["LucerneCore"],
        path: "Tests/LucerneCoreTests"
    )
]

#if os(macOS)
products += [
    .executable(name: "Lucerne", targets: ["Lucerne"]),
    .library(name: "LucerneKit", targets: ["LucerneKit"])
]
targets += [
    .executableTarget(
        name: "Lucerne",
        dependencies: ["LucerneKit"],
        path: "Sources/Lucerne",
        // Bundled so the About / Welcome windows show the real artwork even when
        // running unbundled (where NSApp.applicationIconImage is the generic icon).
        resources: [.copy("Resources/icon.png")]
    ),
    .target(
        name: "LucerneKit",
        dependencies: ["LucerneCore"],
        path: "Sources/LucerneKit"
    ),
    .testTarget(
        name: "LucerneKitTests",
        dependencies: ["LucerneKit"],
        path: "Tests/LucerneKitTests"
    )
]
#endif

let package = Package(
    name: "Lucerne",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
