// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "freescene_provider_host", platforms: [.macOS("13.0")],
    products: [.library(name: "freescene-provider-host", targets: ["freescene_provider_host"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [.target(name: "freescene_provider_host", dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
        publicHeadersPath: "include", linkerSettings: [.linkedFramework("WebKit")])]
)
