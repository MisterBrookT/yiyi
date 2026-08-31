// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "yiyi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YiyiCore", targets: ["YiyiCore"]),
        .executable(name: "yiyi", targets: ["Yiyi"])
    ],
    targets: [
        .target(name: "YiyiCore"),
        .executableTarget(
            name: "Yiyi",
            dependencies: ["YiyiCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "YiyiCoreTests", dependencies: ["YiyiCore"])
    ]
)
