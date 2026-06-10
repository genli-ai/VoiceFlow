import Foundation

// MARK: - Qwen 模型选项

struct QwenModelOption {
    let repo: String       // HuggingFace 仓库 ID
    let title: String
    let sizeNote: String
}

enum QwenModels {
    static var all: [QwenModelOption] { [
        QwenModelOption(repo: "mlx-community/Qwen3-ASR-0.6B-6bit",
                        title: tr("Qwen3-ASR 0.6B 6bit（推荐，快）", "Qwen3-ASR 0.6B 6-bit (recommended, fast)"),
                        sizeNote: tr("约 860 MB", "~860 MB")),
        QwenModelOption(repo: "mlx-community/Qwen3-ASR-1.7B-4bit",
                        title: tr("Qwen3-ASR 1.7B 4bit（更准，稍慢）", "Qwen3-ASR 1.7B 4-bit (more accurate, slower)"),
                        sizeNote: tr("约 1.1 GB", "~1.1 GB")),
    ] }
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
final class QwenEngine: SpeechEngine, @unchecked Sendable {

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
    private var readyDirPath: String?

    var isModelLoaded: Bool { loadTask != nil }
    var isModelReady: Bool {
        let dir = modelDirectory.path
        return loadTask != nil && loadedDirPath == dir && readyDirPath == dir
    }

    /// 主线程调用：获取（或创建）模型加载任务，含 Metal 预热
    private func ensureLoadTask() -> Task<Qwen3ASRSTT, Error> {
        let dir = modelDirectory
        let dirPath = dir.path
        if let task = loadTask, loadedDirPath == dir.path {
            return task
        }
        loadTask = nil
        readyDirPath = nil
        let task = Task {
            try await Qwen3ASRSTT.loadWithWarmup(from: dir)
        }
        loadTask = task
        loadedDirPath = dirPath
        Task { [weak self] in
            do {
                _ = try await task.value
                guard let engine = self else { return }
                await MainActor.run {
                    guard engine.loadedDirPath == dirPath else { return }
                    engine.readyDirPath = dirPath
                }
            } catch {
                // transcribe() reports the concrete error and clears the failed task.
            }
        }
        return task
    }

    /// HF 上的 Qwen3-ASR 量化仓库普遍缺 tokenizer.json（swift-transformers 必需），
    /// 从 App 自带资源里补一份到模型目录
    private func ensureTokenizerFile() -> VFError? {
        let dest = modelDirectory.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: dest.path) { return nil }
        guard let bundled = Bundle.main.url(forResource: "tokenizer", withExtension: "json",
                                            subdirectory: "QwenTokenizer") else {
            return VFError(tr("缺少分词器资源。请先运行 scripts/Generate Qwen Tokenizer.command 再重新安装", "Tokenizer resource missing — run scripts/Generate Qwen Tokenizer.command and reinstall"))
        }
        do {
            try FileManager.default.copyItem(at: bundled, to: dest)
            return nil
        } catch {
            return VFError(tr("无法写入 tokenizer.json：", "Cannot write tokenizer.json: ") + error.localizedDescription)
        }
    }

    func preload() {
        guard isModelAvailable, ensureTokenizerFile() == nil else { return }
        _ = ensureLoadTask()
    }

    func unloadModel() {
        loadTask = nil
        loadedDirPath = nil
        readyDirPath = nil
        Qwen3ASRSTT.flushMemoryPool()
    }

    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void) {
        guard isModelAvailable else {
            DispatchQueue.main.async {
                completion(.failure(VFError(tr("Qwen 模型未下载，请在 设置 → 识别 中下载", "Qwen model not downloaded — see Settings → Recognition"))))
            }
            return
        }
        if let tokErr = ensureTokenizerFile() {
            DispatchQueue.main.async { completion(.failure(tokErr)) }
            return
        }

        // 词汇表直接作为热词上下文喂给模型。
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
                    self?.readyDirPath = nil
                    completion(.failure(VFError(tr("Qwen 模型加载失败：", "Qwen model failed to load: ") + String(message.prefix(120)))))
                }
                return
            }
            await MainActor.run { [weak self] in
                self?.readyDirPath = self?.loadedDirPath
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
                    completion(.failure(VFError(tr("Qwen 识别失败：", "Qwen transcription failed: ") + String(message.prefix(120)))))
                }
            }
        }
    }
}

#else

/// Intel 机型占位实现：V2 的 Qwen/MLX 引擎只支持 Apple Silicon。
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
            completion(.failure(VFError(tr("VoiceFlow 仅支持 Apple Silicon", "VoiceFlow requires Apple Silicon"))))
        }
    }
}

#endif
