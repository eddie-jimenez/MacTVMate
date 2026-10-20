// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTVMate",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CMPV",
            pkgConfig: "mpv",
            providers: [.brew(["mpv"])]
        ),
        .executableTarget(
            name: "MacTVMate",
            dependencies: ["CMPV"],
            swiftSettings: [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib"])]
        ),
    ]
)
