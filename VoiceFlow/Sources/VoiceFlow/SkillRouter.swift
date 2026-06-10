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

enum SkillIntent {
    case dictation                              // 普通语音输入
    case modifySelection(instruction: String)   // 修改选中文本
    case replyDraft(instruction: String)        // 草拟回复
}

enum SkillRouter {

    /// 根据口述文本和当前是否有选区，判断这次语音的意图。
    /// 规则刻意保守：宁可漏判（降级为普通输入），不可误判（把要输入的话当成指令）。
    static func route(text: String, hasSelection: Bool) -> SkillIntent {
        guard Settings.shared.skillsEnabled else { return .dictation }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .dictation }
        let compact = t.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: ",", with: "")
            .lowercased()

        // 帮我回复：必须以触发短语开头
        let replyTriggers = ["帮我回复", "帮我回一下", "帮我回个", "帮我答复", "helpmereply", "draftareply"]
        for trigger in replyTriggers where compact.hasPrefix(trigger) {
            return .replyDraft(instruction: t)
        }

        // 选区修改：必须同时满足三个条件——有活动选区、是短指令（≤40字）、以修改类动词开头
        if hasSelection, t.count <= 40 {
            let modifyPrefixes = [
                "改", "把", "修改", "润色", "精简", "压缩", "扩写", "翻译", "总结",
                "调整", "换成", "去掉", "缩短", "加长", "重写",
                "makeit", "rewrite", "translate", "shorten", "summarize", "fix", "simplify",
            ]
            for prefix in modifyPrefixes where compact.hasPrefix(prefix) {
                return .modifySelection(instruction: t)
            }
        }

        return .dictation
    }
}
