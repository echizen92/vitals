// swift-tools-version: 6.0
import PackageDescription

// VitalsKit holds every piece of logic in Vitals so it can be unit-tested away from the app:
// probes, sampling, log import, diagnosis, benchmarks, hardware-test model and report export.
// VitalsDesign is the design system (colours, type, components, motion primitives); it is a
// separate target so the logic target never imports SwiftUI and its tests run on the Mac.
let package = Package(
    name: "VitalsKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VitalsKit", targets: ["VitalsKit"]),
        .library(name: "VitalsDesign", targets: ["VitalsDesign"]),
    ],
    targets: [
        .target(
            name: "VitalsKit",
            path: "Sources/VitalsKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "VitalsDesign",
            dependencies: ["VitalsKit"],
            path: "Sources/VitalsDesign"
        ),
        .testTarget(
            name: "VitalsKitTests",
            dependencies: ["VitalsKit"],
            path: "Tests/VitalsKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
