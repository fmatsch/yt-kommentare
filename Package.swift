// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YTKommentare",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "YTKommentare", path: "Sources/YTKommentare")
    ]
)
