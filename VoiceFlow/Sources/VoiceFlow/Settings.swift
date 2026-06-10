import Foundation

// MARK: - 热键选项

enum HotkeyChoice: String, CaseIterable {
    case rightOption
    case rightCommand
    case rightControl

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }

    var flagMask: UInt {
        switch self {
        case .rightOption: return 1 << 19   // NSEvent.ModifierFlags.option
        case .rightCommand: return 1 << 20  // NSEvent.ModifierFlags.command
        case .rightControl: return 1 << 18  // NSEvent.ModifierFlags.control
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: return "右 Option (⌥)"
        case .rightCommand: return "右 Command (⌘)"
        case .rightControl: return "右 Control (⌃)"
        }
    }

    var shortSymbol: String {
        switch self {
        case .rightOption: return "右⌥"
        case .rightCommand: return "右⌘"
        case .rightControl: return "右⌃"
        }
    }
}

// MARK: - 触发模式

enum TriggerMode: String, CaseIterable {
    case toggle  // 按一下开始 / 再按一下结束
    case hold    // 按住说话，松开结束

    var displayName: String {
        switch self {
        case .toggle: return "按一下开始 / 再按结束"
        case .hold: return "按住说话，松开结束"
        }
    }
}

// MARK: - 润色档位

enum PolishLevel: String, CaseIterable {
    case off    // 仅本地识别
    case light  // 标准润色
    case deep   // 深度润色（重组逻辑）

    var displayName: String {
        switch self {
        case .off: return "仅识别（最快，不联网）"
        case .light: return "标准润色（去口头禅、修错别字）"
        case .deep: return "深度润色（重组逻辑、整理表达）"
        }
    }
}

// MARK: - 设置键

enum SettingsKeys {
    static let hotkey = "hotkey"
    static let triggerMode = "triggerMode"
    static let polishEnabled = "polishEnabled"
    static let polishLevel = "polishLevel"
    static let openaiBaseURL = "openaiBaseURL"
    static let chatModel = "chatModel"
    static let customPolishRules = "customPolishRules"
    static let customVocabulary = "customVocabulary"
    static let playSounds = "playSounds"
    static let restoreClipboard = "restoreClipboard"
    static let smartLevel = "smartLevel"
    static let qwenModelRepo = "qwenModelRepo"
}

// MARK: - 设置

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            SettingsKeys.hotkey: HotkeyChoice.rightOption.rawValue,
            SettingsKeys.triggerMode: TriggerMode.toggle.rawValue,
            SettingsKeys.polishEnabled: true,
            SettingsKeys.polishLevel: PolishLevel.light.rawValue,
            SettingsKeys.openaiBaseURL: "https://api.openai.com/v1",
            SettingsKeys.chatModel: "gpt-5.4-mini",
            SettingsKeys.customPolishRules: "",
            SettingsKeys.customVocabulary: "",
            SettingsKeys.playSounds: true,
            SettingsKeys.restoreClipboard: true,
            SettingsKeys.smartLevel: false,
            SettingsKeys.qwenModelRepo: QwenModels.defaultRepo,
        ])

        // 一次性迁移：统一默认模型为 gpt-5.4-mini（质量与速度的平衡点）
        if !d.bool(forKey: "migratedModelToMini2") {
            let current = d.string(forKey: SettingsKeys.chatModel)
            if current == nil || current == "gpt-4o-mini" || current == "gpt-5.4-nano" {
                d.set("gpt-5.4-mini", forKey: SettingsKeys.chatModel)
            }
            d.set(true, forKey: "migratedModelToMini2")
        }
    }

    var hotkey: HotkeyChoice {
        get { HotkeyChoice(rawValue: d.string(forKey: SettingsKeys.hotkey) ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: SettingsKeys.hotkey) }
    }

    var triggerMode: TriggerMode {
        get { TriggerMode(rawValue: d.string(forKey: SettingsKeys.triggerMode) ?? "") ?? .toggle }
        set { d.set(newValue.rawValue, forKey: SettingsKeys.triggerMode) }
    }

    var polishEnabled: Bool {
        get { d.bool(forKey: SettingsKeys.polishEnabled) }
        set { d.set(newValue, forKey: SettingsKeys.polishEnabled) }
    }

    var polishLevel: PolishLevel {
        get { PolishLevel(rawValue: d.string(forKey: SettingsKeys.polishLevel) ?? "") ?? .light }
        set { d.set(newValue.rawValue, forKey: SettingsKeys.polishLevel) }
    }

    var openaiBaseURL: String {
        get { d.string(forKey: SettingsKeys.openaiBaseURL) ?? "https://api.openai.com/v1" }
        set { d.set(newValue, forKey: SettingsKeys.openaiBaseURL) }
    }

    var chatModel: String {
        get { d.string(forKey: SettingsKeys.chatModel) ?? "gpt-5.4-mini" }
        set { d.set(newValue, forKey: SettingsKeys.chatModel) }
    }

    var customPolishRules: String {
        get { d.string(forKey: SettingsKeys.customPolishRules) ?? "" }
        set { d.set(newValue, forKey: SettingsKeys.customPolishRules) }
    }

    /// 逗号/换行分隔的专有词汇
    var customVocabulary: String {
        get { d.string(forKey: SettingsKeys.customVocabulary) ?? "" }
        set { d.set(newValue, forKey: SettingsKeys.customVocabulary) }
    }

    var vocabularyTerms: [String] {
        customVocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var playSounds: Bool {
        get { d.bool(forKey: SettingsKeys.playSounds) }
        set { d.set(newValue, forKey: SettingsKeys.playSounds) }
    }

    var restoreClipboard: Bool {
        get { d.bool(forKey: SettingsKeys.restoreClipboard) }
        set { d.set(newValue, forKey: SettingsKeys.restoreClipboard) }
    }

    /// 智能档位：按当前应用自动选择润色档
    var smartLevelEnabled: Bool {
        get { d.bool(forKey: SettingsKeys.smartLevel) }
        set { d.set(newValue, forKey: SettingsKeys.smartLevel) }
    }

    /// Qwen 模型 HF 仓库 ID
    var qwenModelRepo: String {
        get { d.string(forKey: SettingsKeys.qwenModelRepo) ?? QwenModels.defaultRepo }
        set { d.set(newValue, forKey: SettingsKeys.qwenModelRepo) }
    }

}
