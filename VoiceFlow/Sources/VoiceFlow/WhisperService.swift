import Foundation
import whisper

/// 本地 whisper.cpp 语音识别（完全离线，Metal 加速）
final class WhisperService {

    static let shared = WhisperService()

    private var ctx: OpaquePointer?
    private var loadedModelPath: String?
    private let queue = DispatchQueue(label: "com.ligen.voiceflow.whisper", qos: .userInitiated)

    private init() {
        // 关闭 whisper.cpp 的日志输出
        whisper_log_set({ _, _, _ in }, nil)
    }

    var modelURL: URL {
        Paths.modelsDir.appendingPathComponent(Settings.shared.modelFileName)
    }

    var isModelAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// 应用启动后在后台预加载模型，消除第一次听写的等待
    func preload() {
        let modelPath = modelURL.path
        queue.async { [weak self] in
            _ = self?.ensureLoaded(modelPath: modelPath)
        }
    }

    /// 在 whisper 队列上调用：确保模型已加载
    private func ensureLoaded(modelPath: String) -> VFError? {
        if ctx != nil && loadedModelPath == modelPath { return nil }
        if let old = ctx {
            whisper_free(old)
            ctx = nil
            loadedModelPath = nil
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return VFError("识别模型未下载，请在 设置 → 识别 中下载")
        }
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        guard let newCtx = whisper_init_from_file_with_params(modelPath, cparams) else {
            return VFError("模型加载失败，文件可能损坏，请重新下载")
        }
        ctx = newCtx
        loadedModelPath = modelPath
        return nil
    }

    /// 识别。completion 在主线程回调。
    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void) {
        let modelPath = modelURL.path
        let language = Settings.shared.language
        let vocabTerms = Settings.shared.vocabularyTerms
        let fastDecode = Settings.shared.fastDecode

        queue.async { [weak self] in
            guard let self = self else { return }

            func finish(_ result: Result<String, VFError>) {
                DispatchQueue.main.async { completion(result) }
            }

            // 加载（或复用）模型
            if let err = self.ensureLoaded(modelPath: modelPath) {
                finish(.failure(err))
                return
            }
            guard let ctx = self.ctx else {
                finish(.failure(VFError("模型未加载")))
                return
            }

            var audio = samples

            // 音量归一化：说话声音小时自动增益（峰值拉到 0.9，最大放大 25 倍），
            // 明显改善轻声说话的识别率
            var peak: Float = 0
            for v in audio {
                let a = abs(v)
                if a > peak { peak = a }
            }
            if peak > 0.0005 && peak < 0.6 {
                let gain = min(0.9 / peak, 25.0)
                if gain > 1.05 {
                    for i in 0..<audio.count {
                        audio[i] *= gain
                    }
                }
            }

            // whisper 要求至少约 1 秒音频，不足则补静音
            let minSamples = 19200  // 1.2s @ 16kHz
            if audio.count < minSamples {
                audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
            }

            // 默认束搜索解码（中英混合准确率好、复读幻觉少）；
            // "速度优先"开关切换为贪心解码，快 2-3 倍
            var params = whisper_full_default_params(
                fastDecode ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH)
            if fastDecode {
                params.greedy.best_of = 1
            } else {
                params.beam_search.beam_size = 5
                params.greedy.best_of = 5
            }
            params.print_progress = false
            params.print_realtime = false
            params.print_special = false
            params.print_timestamps = false
            params.translate = false
            params.no_context = true
            params.suppress_blank = true
            params.temperature = 0.0
            let cores = ProcessInfo.processInfo.activeProcessorCount
            params.n_threads = Int32(max(2, min(8, cores - 2)))

            // 语言
            let langCString = strdup(language)  // "zh" / "en" / "auto"
            params.language = UnsafePointer(langCString)

            // 用 initial_prompt 引导：输出简体中文 + 用户专有词汇
            var promptText = ""
            if language == "zh" {
                // 仅在明确选了中文时，用中英混排示例引导保留英文原文、输出简体。
                // 自动检测模式不加语言偏置，否则说其他语言会被往中文上带。
                promptText = "以下是简体中文和 English 混合的口述，英文词保留原文，比如：我们用 Python 调用 GPT 的 API 做了一个 demo。"
            }
            if !vocabTerms.isEmpty {
                promptText += "常用词汇：" + vocabTerms.joined(separator: "、") + "。"
            }
            if promptText.count > 400 {
                promptText = String(promptText.prefix(400))
            }
            var promptCString: UnsafeMutablePointer<CChar>? = nil
            if !promptText.isEmpty {
                promptCString = strdup(promptText)
                params.initial_prompt = UnsafePointer(promptCString)
            }

            let status = audio.withUnsafeBufferPointer { ptr in
                whisper_full(ctx, params, ptr.baseAddress, Int32(audio.count))
            }

            free(langCString)
            if let p = promptCString { free(p) }

            guard status == 0 else {
                finish(.failure(VFError("语音识别失败（错误码 \(status)）")))
                return
            }

            var text = ""
            var lastSegment = ""
            let n = whisper_full_n_segments(ctx)
            var i: Int32 = 0
            while i < n {
                if let cstr = whisper_full_get_segment_text(ctx, i) {
                    let seg = String(cString: cstr)
                    // 跳过与上一段完全相同的段落（whisper 复读幻觉）
                    let trimmed = seg.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != lastSegment {
                        text += seg
                        lastSegment = trimmed
                    }
                }
                i += 1
            }

            let cleaned = Self.cleanup(text)
            finish(.success(cleaned))
        }
    }

    /// 去掉 whisper 偶尔输出的标记和幻觉片段
    private static func cleanup(_ text: String) -> String {
        var t = text
        // 去掉 [BLANK_AUDIO]、(字幕) 之类的标记
        for pattern in ["\\[[^\\]]*\\]", "\\([^)]*\\)"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
            }
        }
        // 折叠"复读机"式重复：同一短语连续出现 3 次以上时只保留一次
        if let regex = try? NSRegularExpression(pattern: "(.{2,24}?)\\1{2,}", options: [.dotMatchesLineSeparators]) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1")
        }
        // 整大段内容被原样复述一遍（whisper 长句幻觉）也只保留一次
        if let regex = try? NSRegularExpression(pattern: "(.{12,400}?)\\1+", options: [.dotMatchesLineSeparators]) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 释放模型内存
    func unloadModel() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let old = self.ctx {
                whisper_free(old)
                self.ctx = nil
                self.loadedModelPath = nil
            }
        }
    }

    var isModelLoaded: Bool {
        ctx != nil
    }
}
