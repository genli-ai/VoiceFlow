import Foundation

// MARK: - 识别引擎抽象

protocol SpeechEngine: AnyObject {
    var engineName: String { get }
    var isModelAvailable: Bool { get }
    var isModelLoaded: Bool { get }
    func preload()
    func unloadModel()
    /// samples：16kHz 单声道 Float32。completion 在主线程回调。
    func transcribe(samples: [Float], completion: @escaping (Result<String, VFError>) -> Void)
}

// MARK: - 引擎选择

enum EngineChoice: String, CaseIterable {
    case auto
    case qwen
    case whisper

    var displayName: String {
        switch self {
        case .auto: return "自动（有 Qwen 模型则优先）"
        case .qwen: return "Qwen3-ASR（2026 新一代，中文最强）"
        case .whisper: return "Whisper（经典，兼容性好）"
        }
    }
}

enum EngineRouter {
    /// 按设置返回当前应使用的引擎
    static var current: SpeechEngine {
        switch Settings.shared.engine {
        case .whisper:
            return WhisperService.shared
        case .qwen:
            return QwenEngine.shared
        case .auto:
            return QwenEngine.shared.isModelAvailable ? QwenEngine.shared : WhisperService.shared
        }
    }
}
