// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Gevun",
    platforms: [.iOS("27.0")],
    products: [.library(name: "Gevun", targets: ["Gevun"])],
    dependencies: [.package(path: "Core")],
    targets: [
        .target(
            name: "Gevun", dependencies: [.product(name: "GevunCore", package: "Core")],
            path: "Gevun", exclude: ["Info.plist", "PrivacyInfo.xcprivacy", "Assets.xcassets"])
    ],
    swiftLanguageModes: [.v5]
)
