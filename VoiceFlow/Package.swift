// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceFlow",
    platforms: [
        .macOS("13.3")
    ],
    targets: [
        .executableTarget(
            name: "VoiceFlow",
            dependencies: ["whisper"],
            path: "Sources/VoiceFlow",
            swiftSettings: [
                // 源码按 Swift 5 语言模式编译（避免 Swift 6 严格并发检查）
                .unsafeFlags(["-swift-version", "5"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        // 预编译的 whisper.cpp（含 Metal 加速），由安装脚本下载到 Frameworks/ 目录
        .binaryTarget(
            name: "whisper",
            path: "Frameworks/whisper.xcframework"
        )
    ]
)
