import Foundation
import Combine

// MARK: - 界面语言（中文 / English 二选一）
// 设计：界面上只有两个选项，没有"跟随系统"——但首次启动的默认值取自系统语言。
// 字符串采用行内双语 tr("中文", "English")，切换即时生效，不依赖 .lproj 机制。

enum AppLanguage: String, CaseIterable {
    case zh
    case en

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: SettingsKeys.appLanguage)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: SettingsKeys.appLanguage),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            // 首次启动：按系统语言初始化（之后由用户在设置里二选一）
            let preferred = Locale.preferredLanguages.first ?? "en"
            language = preferred.hasPrefix("zh") ? .zh : .en
        }
    }
}

/// 行内双语：界面文字的唯一出口
func tr(_ zh: String, _ en: String) -> String {
    L10n.shared.language == .zh ? zh : en
}
