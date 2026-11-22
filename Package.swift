// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AscendCore", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AscendCore", targets: ["AscendCore"])],
    targets: [.target(name: "AscendCore"), .testTarget(name: "AscendCoreTests", dependencies: ["AscendCore"])])
