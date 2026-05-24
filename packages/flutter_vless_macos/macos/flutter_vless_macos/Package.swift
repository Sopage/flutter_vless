// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_vless_macos",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "flutter-vless-macos", targets: ["flutter_vless_macos"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "flutter_vless_macos",
            dependencies: [
                "XRay",
                "CXRay"
            ],
            linkerSettings: [
                .linkedLibrary("resolv")
            ]
        ),
        .target(
            name: "CXRay",
            dependencies: ["XRay"],
            publicHeadersPath: "include"
        ),
        .binaryTarget(
            name: "XRay",
            url: "https://github.com/XIIIFOX/flutter_vless/releases/download/xray-macos-v26.5.9/XRay.xcframework.zip",
            checksum: "01c2dee70aad1565ce196682443462291fb35b2ff5639e15d8fef577c0093034"
        )
    ]
)
