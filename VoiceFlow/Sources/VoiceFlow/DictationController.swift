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

    private static func smartLevel(for bundleID: String, fallback: PolishLevel) -> PolishLevel {
        if chatApps.contains(bundleID) { return .light }
        if writingApps.contains(bundleID) { return .deep }
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

    func cancel() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        phase = .idle
        overlay.hide()
        Sounds.playCancel()
    }

    var isRecording: Bool { phase == .recording }

    // MARK: - 流程

    private func startRecording() {
        // 检查模型
        guard QwenEngine.shared.isModelAvailable else {
            overlay.flashError("识别模型未下载，请在设置中下载")
            Sounds.playError()
            onNeedSettings?()
            return
        }
        // 检查辅助功能权限（粘贴需要）——每次启动只提示一次，不反复骚扰
        if !Permissions.isAccessibilityTrusted && !didPromptAccessibility {
            didPromptAccessibility = true
            Permissions.promptAccessibility()
        }
        // 检查麦克风权限
        let alreadyAuthorized = Permissions.microphoneGranted
        let mode = Settings.shared.triggerMode
        Permissions.ensureMicrophone { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.overlay.flashError("没有麦克风权限，请在 系统设置 → 隐私 中开启")
                Sounds.playError()
                Permissions.openMicrophoneSettings()
                return
            }
            // 按住模式下，如果权限是这次异步授权的，按键早已松开，
            // 此时不能自动开始录音（否则没人来停止它），让用户重新按一次。
            if mode == .hold && !alreadyAuthorized {
                self.overlay.flashSuccess("麦克风已授权，请再按住说话")
                return
            }
            guard self.phase == .idle else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication
            self.targetBundleID = frontmost?.bundleIdentifier ?? ""
            self.targetAppName = frontmost?.localizedName ?? ""
            self.recorder.onLevel = { [weak self] level in
                DispatchQueue.main.async {
                    self?.overlay.state.pushLevel(level)
                }
            }
            do {
                try self.recorder.start()
            } catch {
                let message = (error as? VFError)?.message ?? error.localizedDescription
                self.overlay.flashError(message)
                Sounds.playError()
                return
            }
            self.phase = .recording
            self.overlay.showRecording()
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
        overlay.showProcessing("识别中…")
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
                    self.overlay.flashError("没有听到内容")
                    return
                }
                var level = Settings.shared.polishLevel
                // 智能档位只在手动档为标准/深度时介入；手动选了"仅识别"= 永不联网，智能档位让位
                if Settings.shared.smartLevelEnabled, level != .off {
                    level = Self.smartLevel(for: self.targetBundleID, fallback: level)
                }
                if level != .off, KeychainHelper.loadAPIKey() != nil {
                    var label = level == .deep ? "深度润色中…" : "润色中…"
                    if Settings.shared.smartLevelEnabled, !self.targetAppName.isEmpty {
                        label += "（\(self.targetAppName)）"
                    }
                    self.overlay.showProcessing(label)
                    let tPolish = Date()
                    PolishService.polish(rawText, level: level) { [weak self] polished, failure in
                        guard let self = self else { return }
                        let polishSeconds = Date().timeIntervalSince(tPolish)
                        let timing = String(format: "识别 %.1fs · 润色 %.1fs", asrSeconds, polishSeconds)
                        if let polished = polished {
                            self.deliver(raw: rawText, final: polished, note: "已输入（\(timing)）",
                                         allowClipboardRestore: !isColdStart)
                        } else {
                            self.deliver(raw: rawText, final: rawText,
                                         note: "润色失败（\(failure ?? "未知")），已输出识别原文",
                                         warning: true,
                                         allowClipboardRestore: !isColdStart)
                        }
                    }
                } else {
                    let timing = String(format: "识别 %.1fs", asrSeconds)
                    self.deliver(raw: rawText, final: rawText, note: "已输入（\(timing)）",
                                 allowClipboardRestore: !isColdStart)
                }
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
                self.overlay.flashError("窗口已切换，文本已复制到剪贴板——按 ⌘V 粘贴")
                Sounds.playError()
            }
        }
    }

}
