import Foundation

// MARK: - 输出场景分类（深度润色与技能共用）

enum AppScene: String {
    case chat, email, document, code, unknown

    var styleHint: String {
        switch self {
        case .chat: return "chat（即时聊天）：简洁自然，像真人发消息，不需要称呼和落款。"
        case .email: return "email（邮件）：补全合适的称呼和简洁收尾，得体但不过度客套。"
        case .document: return "document（文档）：结构清晰、书面化表达。"
        case .code: return "code（代码工具）：保留技术术语、命令、变量名原文，表达简洁。"
        case .unknown: return ""
        }
    }
}

enum SceneClassifier {
    private static let chatApps: Set<String> = [
        "com.tencent.xinWeChat", "com.tencent.qq", "ru.keepcoder.Telegram",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS",
        "com.alibaba.DingTalkMac", "com.electron.lark", "com.larksuite.larkApp",
        "net.whatsapp.WhatsApp", "com.microsoft.teams2",
    ]
    private static let emailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac", "com.superhuman.electron",
    ]
    private static let documentApps: Set<String> = [
        "com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.Notes",
        "notion.id", "md.obsidian", "com.lukilabs.lukiapp",
        "com.apple.TextEdit", "com.ulyssesapp.mac",
    ]
    private static let codeApps: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]

    static func scene(for bundleID: String) -> AppScene {
        if chatApps.contains(bundleID) { return .chat }
        if emailApps.contains(bundleID) { return .email }
        if documentApps.contains(bundleID) { return .document }
        if codeApps.contains(bundleID) { return .code }
        return .unknown
    }
}

// MARK: - 语音技能路由（V3）
// 意图区分靠手势而不靠内容：轻点 = 纯输入（永不解析指令），按住 = 指令模式。
// 因此这里只需要在指令模式内部区分"回复类"和"修改类"。

enum SkillRouter {

    /// 指令是否为"帮我回复"类
    static func isReplyTrigger(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: ",", with: "")
            .lowercased()
        let triggers = ["帮我回复", "帮我回一下", "帮我回个", "帮我答复", "回复他", "回复她",
                        "helpmereply", "draftareply", "replyto"]
        return triggers.contains { compact.hasPrefix($0) }
    }
}
