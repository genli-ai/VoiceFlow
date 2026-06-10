// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceFlow",
    platforms: [
        // Qwen3-ASR(MLX) 引擎要求 macOS 15+、Apple Silicon
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
                .product(name: "MLXASR", package: "mlx-swift-asr"),
            ],
            path: "Sources/VoiceFlow",
            swiftSettings: [
                // 源码按 Swift 5 语言模式编译（避免 Swift 6 严格并发检查）
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
