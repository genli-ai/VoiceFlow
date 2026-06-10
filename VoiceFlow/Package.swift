// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceFlow",
    platforms: [
        // V2：Qwen3-ASR(MLX) 引擎要求 macOS 15+；Intel/老系统请使用 V1 (main 分支)
        .macOS("15.0")
    ],
    dependencies: [
        // Qwen3-ASR 推理引擎（MLX），锁定 commit 保证可复现
        .package(url: "https://github.com/ontypehq/mlx-swift-asr",
                 revision: "f8ea5e6e76824eae903580fcfab0ef15e207b479")
    ],
    targets: [
        .executableTarget(
            name: "VoiceFlow",
            dependencies: [
                "whisper",
                .product(name: "MLXASR", package: "mlx-swift-asr"),
            ],
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
