// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GevunCore", platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "GevunCore", targets: ["GevunCore"])],
    targets: [.target(name: "GevunCore"), .testTarget(name: "GevunCoreTests", dependencies: ["GevunCore"])],
    swiftLanguageModes: [.v5])
