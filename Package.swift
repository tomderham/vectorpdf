// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VectorPDF",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MuPDFBridge", targets: ["MuPDFBridge"]),
        .library(name: "PDFEngine", targets: ["PDFEngine"]),
        .executable(name: "VectorPDF", targets: ["VectorPDF"]),
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
        .target(
            name: "PDFEngine",
            dependencies: ["MuPDFBridge"]
        ),
        .executableTarget(
            name: "VectorPDF",
            dependencies: ["PDFEngine"]
        ),
        .testTarget(
            name: "PDFEngineTests",
            dependencies: ["PDFEngine"]
        )
    ]
)
