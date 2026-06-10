import Foundation

// MARK: - Qwen 模型选项

struct QwenModelOption {
    let repo: String       // HuggingFace 仓库 ID
    let title: String
    let sizeNote: String
}

enum QwenModels {
    static let all: [QwenModelOption] = [
        QwenModelOption(repo: "mlx-community/Qwen3-ASR-0.6B-6bit",
                        title: "Qwen3-ASR 0.6B 6bit（推荐，快）",
                        sizeNote: "约 550 MB"),
        QwenModelOption(repo: "mlx-community/Qwen3-ASR-1.7B-4bit",
                        title: "Qwen3-ASR 1.7B 4bit（更准，稍慢）",
                        sizeNote: "约 1.1 GB"),
    ]
    static let defaultRepo = "mlx-community/Qwen3-ASR-0.6B-6bit"

    /// 模型仓库在本地的存放目录
    static func localDirectory(for repo: String) -> URL {
        Paths.modelsDir.appendingPathComponent(
            repo.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
    }
}

#if arch(arm64)

import MLXASR

/// Qwen3-ASR 本地识别引擎（MLX，Apple Silicon 专属）
final class QwenEngine: SpeechEngine {

    static let shared = QwenEngine()
    private init() {}

    var engineName: String { "Qwen3-ASR" }

    private var modelDirectory: URL {
        QwenModels.localDirectory(for: Settings.shared.qwenModelRepo)
    }

    var isModelAvailable: Bool {
        let dir = modelDirectory
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.safetensors").path)
            && FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path)
    }

    // 以下状态只在主线程读写
    private var loadTask: Task<Qwen3ASRSTT, Error>?
    private var loadedDirPath: String?

    var isModelLoaded: Bool { loadTask != nil }

    /// 主线程调用：获取（或创建）模型加载任务，含 Metal 预热
    private func ensureLoadTask() -> Task<Qwen3ASRSTT, Error> {
        let dir = modelDirectory
        if let task = loadTask, loadedDirPath == dir.path {
            return task
        }
        loadTask = nil
        let task = Task {
            try await Qwen3ASRSTT.loadWithWarmup(from: dir)
        }
        loadTask = task
        loadedDirPath = dir.path
        return task
    }

    func preload() {
        guard isModelAvailable else { return }
        _ = ensureLoadTask()
    }

    func unloadModel() {
        loadTask = nil
        loadedDirPath = nil
        Qwen3ASRSTT.flushMemoryPool()
    }

    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void) {
        guard isModelAvailable else {
            DispatchQueue.main.async {
                completion(.failure(VFError("Qwen 模型未下载，请在 设置 → 识别 中下载")))
            }
            return
        }

        // 词汇表直接作为热词上下文喂给模型（Qwen3-ASR 原生支持，whisper 做不到的能力）
        let vocabTerms = Settings.shared.vocabularyTerms
        var context: String? = nil
        if !vocabTerms.isEmpty {
            var joined = vocabTerms.joined(separator: "、")
            if joined.count > 800 { joined = String(joined.prefix(800)) }
            context = "常用词汇：" + joined
        }

        let load = ensureLoadTask()
        Task {
            // 第一步：等待模型加载。失败要清掉缓存的 Task，否则之后永远复用失败结果
            let stt: Qwen3ASRSTT
            do {
                stt = try await load.value
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    self?.loadTask = nil
                    self?.loadedDirPath = nil
                    completion(.failure(VFError("Qwen 模型加载失败：\(String(message.prefix(120)))")))
                }
                return
            }
            // 第二步：识别。失败不影响已加载的模型
            do {
                // language 传 nil：Qwen3-ASR 自动检测语言能力很强，且避免语言代码格式不匹配
                let result = try await stt.transcribe(
                    audio: samples,
                    language: nil,
                    context: context,
                    temperature: 0.0
                )
                let cleaned = TextPostProcessor.cleanTranscript(result.text)
                DispatchQueue.main.async { completion(.success(cleaned)) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    completion(.failure(VFError("Qwen 识别失败：\(String(message.prefix(120)))")))
                }
            }
        }
    }
}

#else

/// Intel 机型占位实现：引导用户使用 Whisper 引擎
final class QwenEngine: SpeechEngine {
    static let shared = QwenEngine()
    private init() {}

    var engineName: String { "Qwen3-ASR" }
    var isModelAvailable: Bool { false }
    var isModelLoaded: Bool { false }
    func preload() {}
    func unloadModel() {}
    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void) {
        DispatchQueue.main.async {
            completion(.failure(VFError("Qwen 引擎仅支持 Apple Silicon，请在设置中切换为 Whisper")))
        }
    }
}

#endif
