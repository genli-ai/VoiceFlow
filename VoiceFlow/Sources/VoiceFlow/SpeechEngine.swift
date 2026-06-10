import Foundation

// MARK: - 识别引擎抽象
// 当前唯一实现是 QwenEngine；保留协议是为了将来接入其它引擎（如 FireRedASR）时即插即用。

protocol SpeechEngine: AnyObject {
    var engineName: String { get }
    var isModelAvailable: Bool { get }
    var isModelLoaded: Bool { get }
    func preload()
    func unloadModel()
    /// samples：16kHz 单声道 Float32。completion 在主线程回调。
    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void)
}
