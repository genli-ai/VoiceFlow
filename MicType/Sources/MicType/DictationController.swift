import AppKit

/// 听写主流程：录音 → 本地识别 → AI 润色 → 插入光标处
final class DictationController {

    enum Phase {
        case idle
        case recording
        case processing
    }

    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }

    /// 状态变化回调（主线程），用于菜单栏图标
    var onPhaseChange: ((Phase) -> Void)?
    /// 需要打开设置窗口时的回调
    var onNeedSettings: (() -> Void)?

    private let recorder = AudioRecorder()
    let overlay = OverlayController()
    private var didPromptAccessibility = false
    /// 录音开始时的前台应用（文字将粘贴到这个应用）
    private var targetBundleID = ""
    private var targetAppName = ""
    /// 录音开始时的选中文本（V3 语音技能用；读不到为 nil）
    private var targetSelection: String?
    /// 本次录音是否为"指令模式"（按住快捷键触发）
    private var skillSession = false

    // 智能档位的内置应用分类
    private static let chatApps: Set<String> = [
        "com.tencent.xinWeChat", "com.tencent.qq", "ru.keepcoder.Telegram",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS",
        "com.alibaba.DingTalkMac", "com.electron.lark", "com.larksuite.larkApp",
        "net.whatsapp.WhatsApp", "com.microsoft.teams2",
    ]
    private static let writingApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.microsoft.Word",
        "com.apple.iWork.Pages", "com.apple.Notes", "notion.id", "md.obsidian",
        "com.lukilabs.lukiapp", "com.apple.TextEdit", "com.ulyssesapp.mac",
    ]
    private static let codeApps: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]
    /// 无障碍接口残缺、读选区需要 ⌘C 兜底的应用
    private static let poorAXApps: Set<String> = [
        "com.tencent.xinWeChat", "com.tencent.qq",
    ]

    /// 智能档位（简化版）：代码工具里自动切为仅识别，避免润色干扰技术内容
    private static func smartLevel(for bundleID: String, fallback: PolishLevel) -> PolishLevel {
        if codeApps.contains(bundleID) { return .off }
        return fallback
    }

    // MARK: - 入口

    func toggle() {
        switch phase {
        case .idle: startRecording()
        case .recording: finishRecording()
        case .processing: break  // 处理中忽略
        }
    }

    func holdStart() {
        if phase == .idle { startRecording() }
    }

    func holdEnd() {
        if phase == .recording { finishRecording() }
    }

    /// 指令模式：按住快捷键触发（技能关闭时降级为普通输入）
    func skillHoldStart() {
        guard phase == .idle else { return }
        startRecording(skill: Settings.shared.skillsEnabled)
    }

    func skillHoldEnd() {
        if phase == .recording { finishRecording() }
    }

    func cancel() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        skillSession = false
        phase = .idle
        overlay.hide()
        Sounds.playCancel()
    }

    var isRecording: Bool { phase == .recording }

    // MARK: - 流程

    private func startRecording(skill: Bool = false) {
        // 检查模型
        guard QwenEngine.shared.isModelAvailable else {
            overlay.flashError(tr("识别模型未下载，请在设置中下载",
                                  "Speech model not downloaded — see Settings"))
            Sounds.playError()
            onNeedSettings?()
            return
        }
        // 检查辅助功能权限（粘贴需要）。权限刚打开时 macOS 往往要重启 App 才完全生效。
        guard Permissions.isAccessibilityTrusted else {
            didPromptAccessibility = true
            Permissions.promptAccessibility()
            overlay.flashError(tr("请先开启辅助功能权限，然后重启 MicType",
                                  "Enable Accessibility permission, then restart MicType"))
            Sounds.playError()
            return
        }
        // 检查麦克风权限
        let alreadyAuthorized = Permissions.microphoneGranted
        Permissions.ensureMicrophone { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.overlay.flashError(tr("没有麦克风权限，请在 系统设置 → 隐私 中开启",
                                           "No microphone access — enable it in System Settings → Privacy"))
                Sounds.playError()
                Permissions.openMicrophoneSettings()
                return
            }
            // 首次授权会弹系统窗口并打断焦点，授权期间这一次输入不可靠；
            // 统一让用户再触发一次，避免"历史里有但没粘贴进输入框"。
            if !alreadyAuthorized {
                self.overlay.flashSuccess(tr("麦克风已授权，请再按一次开始",
                                             "Microphone granted — press once more to start"))
                Sounds.playSuccess()
                return
            }
            guard self.phase == .idle else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication
            self.targetBundleID = frontmost?.bundleIdentifier ?? ""
            self.targetAppName = frontmost?.localizedName ?? ""
            // 指令模式才读选区——普通输入完全不碰选区和剪贴板
            self.skillSession = skill
            self.targetSelection = skill ? SelectionReader.readSelectedText() : nil
            // 微信/QQ 的无障碍接口残缺，AX 读不到时用 ⌘C 兜底（异步，不阻塞录音；用完即恢复剪贴板）
            if skill, self.targetSelection == nil,
               Self.poorAXApps.contains(self.targetBundleID) {
                SelectionReader.readSelectedTextWithClipboardFallback { [weak self] text in
                    guard let self = self, self.phase == .recording else { return }
                    self.targetSelection = text
                }
            }
            self.recorder.onLevel = { [weak self] level in
                DispatchQueue.main.async {
                    self?.overlay.state.pushLevel(level)
                }
            }
            do {
                try self.recorder.start()
            } catch {
                let message = (error as? MTError)?.message ?? error.localizedDescription
                self.overlay.flashError(message)
                Sounds.playError()
                return
            }
            self.phase = .recording
            self.overlay.showRecording(label: skill ? tr("正在听指令…", "Listening for command…")
                                                    : tr("正在听…", "Listening…"))
            Sounds.playStart()
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        let samples = recorder.stop()
        let duration = Double(samples.count) / 16000.0

        // 太短当作误触
        guard duration >= 0.4 else {
            phase = .idle
            overlay.hide()
            return
        }

        phase = .processing
        overlay.showProcessing(tr("识别中…", "Transcribing…"))
        let tStart = Date()
        let isColdStart = !QwenEngine.shared.isModelReady

        QwenEngine.shared.transcribe(samples: samples) { [weak self] result in
            guard let self = self else { return }
            let asrSeconds = Date().timeIntervalSince(tStart)
            switch result {
            case .failure(let error):
                self.phase = .idle
                self.overlay.flashError(error.message)
                Sounds.playError()
            case .success(let rawText):
                guard !rawText.isEmpty else {
                    self.phase = .idle
                    self.overlay.flashError(tr("没有听到内容", "Nothing heard"))
                    return
                }
                // 指令模式：这次说的话就是命令。普通输入永远不做指令解析。
                if self.skillSession {
                    self.skillSession = false
                    self.runSkillSession(rawText: rawText, isColdStart: isColdStart)
                    return
                }
                var level = Settings.shared.polishLevel
                // 智能档位只在手动档为标准/深度时介入；手动选了"仅识别"= 永不联网，智能档位让位
                if Settings.shared.smartLevelEnabled, level != .off {
                    level = Self.smartLevel(for: self.targetBundleID, fallback: level)
                }
                if level != .off, KeychainHelper.loadAPIKey() != nil {
                    var label = tr("润色中…", "Polishing…")
                    if Settings.shared.smartLevelEnabled, !self.targetAppName.isEmpty {
                        label += "（\(self.targetAppName)）"
                    }
                    self.overlay.showProcessing(label)
                    let tPolish = Date()
                    let scene = SceneClassifier.scene(for: self.targetBundleID)
                    PolishService.polish(rawText, level: level, scene: scene) { [weak self] polished, failure in
                        guard let self = self else { return }
                        let polishSeconds = Date().timeIntervalSince(tPolish)
                        let timing = String(format: tr("识别 %.1fs · 润色 %.1fs", "ASR %.1fs · polish %.1fs"),
                                            asrSeconds, polishSeconds)
                        if let polished = polished {
                            self.deliver(raw: rawText, final: polished,
                                         note: tr("已输入（", "Inserted (") + timing + tr("）", ")"),
                                         allowClipboardRestore: !isColdStart)
                        } else {
                            self.deliver(raw: rawText, final: rawText,
                                         note: tr("润色失败（", "Polish failed (")
                                             + (failure ?? tr("未知", "unknown"))
                                             + tr("），已输出识别原文", ") — raw transcript inserted"),
                                         warning: true,
                                         allowClipboardRestore: !isColdStart)
                        }
                    }
                } else {
                    let timing = String(format: tr("识别 %.1fs", "ASR %.1fs"), asrSeconds)
                    self.deliver(raw: rawText, final: rawText,
                                 note: tr("已输入（", "Inserted (") + timing + tr("）", ")"),
                                 allowClipboardRestore: !isColdStart)
                }
            }
        }
    }

    // MARK: - V3 语音技能（仅指令模式进入）

    /// 指令分发：说「帮我回复…」→ 草拟回复；有选区 → 把整句话当修改指令；都没有 → 明确报错
    private func runSkillSession(rawText: String, isColdStart: Bool) {
        if SkillRouter.isReplyTrigger(rawText) {
            runReplyDraft(instruction: rawText, raw: rawText)
            return
        }
        if targetSelection != nil {
            runModifySelection(instruction: rawText, raw: rawText, isColdStart: isColdStart)
            return
        }
        // 没选区：当作自由指令——口述任务（草拟邮件/翻译/提问…），结果粘贴到光标处
        runFreeform(instruction: rawText, raw: rawText, isColdStart: isColdStart)
    }

    /// 技能：自由指令——指令模式下的"万能入口"
    private func runFreeform(instruction: String, raw: String, isColdStart: Bool) {
        overlay.showProcessing(tr("执行指令中…", "Running command…"))
        let scene = SceneClassifier.scene(for: targetBundleID)
        AgentService.freeform(instruction: instruction, scene: scene) { [weak self] result, failure in
            guard let self = self else { return }
            if let result = result {
                self.deliver(raw: raw, final: result, note: tr("已输入指令结果", "Command result inserted"),
                             allowClipboardRestore: !isColdStart)
            } else {
                self.phase = .idle
                self.overlay.flashError(tr("指令执行失败（", "Command failed (") + (failure ?? tr("未知", "unknown")) + tr("）", ")"))
                Sounds.playError()
            }
        }
    }

    /// 技能：修改选中文本——结果直接粘贴覆盖仍处于选中状态的文字
    private func runModifySelection(instruction: String, raw: String, isColdStart: Bool) {
        guard let selection = targetSelection else {
            phase = .idle
            overlay.flashError(tr("没有读到选中文本", "Could not read selected text"))
            Sounds.playError()
            return
        }
        overlay.showProcessing(tr("执行指令中…", "Running command…"))
        AgentService.modifySelection(selection, instruction: instruction) { [weak self] result, failure in
            guard let self = self else { return }
            if let result = result {
                self.deliver(raw: raw, final: result, note: tr("已替换选中文本", "Selection replaced"),
                             allowClipboardRestore: !isColdStart)
            } else {
                self.phase = .idle
                self.overlay.flashError(tr("指令执行失败（", "Command failed (") + (failure ?? tr("未知", "unknown")) + tr("）", ")"))
                Sounds.playError()
            }
        }
    }

    /// 技能：帮我回复——基于选中的对方消息草拟回复。
    /// 安全策略：不自动粘贴（焦点通常在消息区而非输入框），复制到剪贴板由用户 ⌘V。
    private func runReplyDraft(instruction: String, raw: String) {
        if let context = targetSelection {
            executeReplyDraft(context: context, instruction: instruction, raw: raw)
            return
        }
        // AX 没读到：此刻焦点仍在目标应用、选区还在，用 ⌘C 兜底再试一次
        overlay.showProcessing(tr("读取选中内容…", "Reading selection…"))
        SelectionReader.readSelectedTextWithClipboardFallback { [weak self] context in
            guard let self = self else { return }
            guard let context = context else {
                self.phase = .idle
                self.overlay.flashError(tr("读不到选中内容：请重新选中要回复的消息再试", "Could not read selection — reselect the message and try again"))
                Sounds.playError()
                return
            }
            self.executeReplyDraft(context: context, instruction: instruction, raw: raw)
        }
    }

    private func executeReplyDraft(context: String, instruction: String, raw: String) {
        overlay.showProcessing(tr("草拟回复中…", "Drafting reply…"))
        let scene = SceneClassifier.scene(for: targetBundleID)
        AgentService.replyDraft(context: context, instruction: instruction, scene: scene) { [weak self] result, failure in
            guard let self = self else { return }
            self.phase = .idle
            if let result = result {
                let final = TextPostProcessor.fixMixedPunctuation(result)
                HistoryStore.shared.add(raw: raw, polished: final)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(final, forType: .string)
                self.overlay.flashSuccess(tr("回复草稿已复制——点到输入框按 ⌘V", "Reply draft copied — click the input field and press ⌘V"))
                Sounds.playSuccess()
            } else {
                self.overlay.flashError(tr("草拟失败（", "Draft failed (") + (failure ?? tr("未知", "unknown")) + tr("）", ")"))
                Sounds.playError()
            }
        }
    }

    private func deliver(raw: String, final text: String, note: String, warning: Bool = false,
                         allowClipboardRestore: Bool = true) {
        let finalText = TextPostProcessor.fixMixedPunctuation(text)
        HistoryStore.shared.add(raw: raw, polished: finalText)
        phase = .idle
        TextInserter.insert(finalText, targetBundleID: targetBundleID,
                            allowClipboardRestore: allowClipboardRestore,
                            conservativePaste: !allowClipboardRestore) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .pasted:
                if warning {
                    self.overlay.flashError(note)
                } else {
                    self.overlay.flashSuccess(note)
                }
                Sounds.playSuccess()
            case .clipboardOnly:
                self.overlay.flashError(tr("窗口已切换，文本已复制到剪贴板——按 ⌘V 粘贴", "Window changed — text copied to clipboard, press ⌘V to paste"))
                Sounds.playError()
            }
        }
    }

}
