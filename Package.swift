// swift-tools-version:5.9
import Foundation
import PackageDescription

// libmpv comes from Homebrew: /opt/homebrew on Apple silicon, /usr/local on Intel.
let brew = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"]
    ?? (FileManager.default.fileExists(atPath: "/opt/homebrew/include/mpv") ? "/opt/homebrew" : "/usr/local")

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
            swiftSettings: [.unsafeFlags(["-Xcc", "-I\(brew)/include"])],
            linkerSettings: [.unsafeFlags(["-L\(brew)/lib"])]
        ),
    ]
)
