// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFMarkCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PDFMarkCore",
            targets: ["PDFMarkCore"]
        )
    ],
    targets: [
        .target(
            name: "PDFMarkCore",
            path: "Sources/PDFMarkCore"
        )
    ]
)
