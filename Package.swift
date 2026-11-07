// swift-tools-version: 6.0
import PackageDescription

// Features that need the macOS 27 SDK (Private Cloud Compute and online models for the Agent)
// compile behind VECTORPDF_MACOS27_SDK. Swift 6.4 ships with that SDK (Xcode 27), so every build —
// swift build, swift run, swift test and the scripts — gets them with it, and none without.
#if compiler(>=6.4)
let macOS27SDK: [SwiftSetting] = [.define("VECTORPDF_MACOS27_SDK")]
#else
let macOS27SDK: [SwiftSetting] = []
#endif

let package = Package(
    name: "VectorPDF",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MuPDFBridge", targets: ["MuPDFBridge"]),
        .library(name: "PDFEngine", targets: ["PDFEngine"]),
        .executable(name: "VectorPDF", targets: ["VectorPDF"]),
        .executable(name: "displayline", targets: ["displayline"]),
    ],
    targets: [
        // Vendored, self-contained MuPDF build (see Vendor/README.md)
        .binaryTarget(
            name: "MuPDF",
            path: "Vendor/MuPDF.xcframework"
        ),
        .target(
            name: "MuPDFBridge",
            dependencies: ["MuPDF"],
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        // The official SyncTeX parser, vendored (see Sources/SyncTeX/README.md)
        .target(
            name: "SyncTeX",
            cSettings: [
                .define("SYNCTEX_USE_LOCAL_HEADER"),
                .unsafeFlags(["-w"])
            ],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "PDFEngine",
            dependencies: ["MuPDFBridge", "SyncTeX", "SyncTeXLink"],
            swiftSettings: macOS27SDK
        ),
        .executableTarget(
            name: "VectorPDF",
            dependencies: ["PDFEngine", "SyncTeXLink"]
        ),
        // Skim-compatible forward-search tool that editors run (bundled in Contents/Helpers)
        .executableTarget(
            name: "displayline",
            dependencies: ["SyncTeXLink"]
        ),
        // The forward-search URL, shared by displayline and the app
        .target(
            name: "SyncTeXLink"
        ),
        .testTarget(
            name: "PDFEngineTests",
            dependencies: ["PDFEngine", "SyncTeXLink"],
            swiftSettings: macOS27SDK
        )
    ]
)
