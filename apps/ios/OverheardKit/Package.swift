// swift-tools-version: 6.0
import PackageDescription

// Detection code shared by the iOS app and the Mac eval harness, so both run
// exactly the same pipeline.
let package = Package(
    name: "OverheardKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OverheardKit", targets: ["OverheardKit"])
    ],
    targets: [
        .target(name: "OverheardKit"),
        .executableTarget(name: "overheard-eval", dependencies: ["OverheardKit"]),
        .testTarget(name: "OverheardKitTests", dependencies: ["OverheardKit"]),
    ]
)
