import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - 设置窗口

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "VoiceFlow 设置"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 480))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 设置界面

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            RecognitionTab()
                .tabItem { Label("识别", systemImage: "waveform") }
            PolishTab()
                .tabItem { Label("AI 润色", systemImage: "wand.and.stars") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @AppStorage(SettingsKeys.hotkey) private var hotkey = HotkeyChoice.rightOption.rawValue
    @AppStorage(SettingsKeys.triggerMode) private var triggerMode = TriggerMode.toggle.rawValue
    @AppStorage(SettingsKeys.playSounds) private var playSounds = true
    @AppStorage(SettingsKeys.restoreClipboard) private var restoreClipboard = true
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var micOK = Permissions.microphoneGranted
    @State private var axOK = Permissions.isAccessibilityTrusted
    private let permTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker("听写快捷键：", selection: $hotkey) {
                    ForEach(HotkeyChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                Picker("触发方式：", selection: $triggerMode) {
                    ForEach(TriggerMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Text("录音中按 Esc 可随时取消。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("开始 / 完成时播放提示音", isOn: $playSounds)
                Toggle("输入后恢复原剪贴板内容", isOn: $restoreClipboard)
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }

            Section {
                HStack {
                    Text("权限：")
                    PermissionBadge(name: "麦克风", ok: micOK)
                    PermissionBadge(name: "辅助功能", ok: axOK)
                    Spacer()
                    Button("打开系统设置") {
                        Permissions.openAccessibilitySettings()
                    }
                }
                .onReceive(permTimer) { _ in
                    micOK = Permissions.microphoneGranted
                    axOK = Permissions.isAccessibilityTrusted
                }
                Text("「辅助功能」权限用于监听快捷键和把文字粘贴到光标处，必须开启。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !axOK {
                    Text("如果系统设置里显示已开启但这里仍是 ✗：是旧版授权失效了。请在 辅助功能 列表中选中 VoiceFlow，点「−」删除，再点「+」重新添加 /Applications/VoiceFlow.app。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct PermissionBadge: View {
    let name: String
    let ok: Bool
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
            Text(name)
        }
        .font(.caption)
    }
}

// MARK: - 识别（Qwen3-ASR）

private struct RecognitionTab: View {
    @AppStorage(SettingsKeys.qwenModelRepo) private var qwenRepo = QwenModels.defaultRepo
    @AppStorage(SettingsKeys.customVocabulary) private var vocabulary = ""
    @ObservedObject private var downloader = QwenModelDownloader.shared
    @State private var refreshTick = 0
    @State private var updateMessage = ""
    @State private var checkingUpdate = false

    private var modelExists: Bool {
        _ = refreshTick
        let dir = QwenModels.localDirectory(for: qwenRepo)
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.safetensors").path)
    }

    var body: some View {
        Form {
            Section {
                Picker("识别模型：", selection: $qwenRepo) {
                    ForEach(QwenModels.all, id: \.repo) { m in
                        Text("\(m.title) · \(m.sizeNote)").tag(m.repo)
                    }
                }
                HStack {
                    Image(systemName: modelExists ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundColor(modelExists ? .green : .orange)
                    Text(modelExists ? "模型已就绪" : "模型未下载")
                    Spacer()
                    if downloader.isDownloading {
                        Button("取消") { downloader.cancel() }
                    } else {
                        Button(modelExists ? "重新下载 / 更新" : "下载模型") {
                            updateMessage = ""
                            QwenEngine.shared.unloadModel()
                            downloader.download(repo: qwenRepo, force: modelExists)
                        }
                        Button(checkingUpdate ? "检查中…" : "检查更新") {
                            checkingUpdate = true
                            updateMessage = ""
                            QwenModelDownloader.checkForUpdate(repo: qwenRepo) { _, message in
                                checkingUpdate = false
                                updateMessage = message
                            }
                        }
                        .disabled(checkingUpdate)
                    }
                }
                if downloader.isDownloading {
                    ProgressView(value: downloader.progress)
                }
                if !downloader.statusText.isEmpty {
                    Text(downloader.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !updateMessage.isEmpty {
                    Text(updateMessage)
                        .font(.caption)
                        .foregroundColor(updateMessage.contains("发现新版本") ? .orange : .secondary)
                }
                Text("Qwen3-ASR（2026）：约 30 种语言 + 22 种中文方言，自动检测语言，识别完全在本机进行。模型来自 HuggingFace（hf-mirror 加速）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("「检查更新」会对比远端仓库版本；发现新版本后点「重新下载 / 更新」即可。专有词汇表是你的本地热词，修改后下次识别立刻生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("专有词汇表（人名、品牌、术语等，用逗号或换行分隔）：")
                    TextEditor(text: $vocabulary)
                        .font(.system(size: 12))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    Text("这些词会作为热词直接送入识别模型，并参与 AI 润色纠错——专有名词识别准确率的第一杠杆，强烈建议填写。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onReceive(downloader.$isDownloading) { _ in
            refreshTick += 1
        }
        .onChange(of: qwenRepo) { _, _ in
            updateMessage = ""
            QwenEngine.shared.unloadModel()
            refreshTick += 1
        }
    }
}

// MARK: - AI 润色

private struct PolishTab: View {
    @AppStorage(SettingsKeys.polishLevel) private var polishLevel = PolishLevel.light.rawValue
    @AppStorage(SettingsKeys.smartLevel) private var smartLevel = false
    @AppStorage(SettingsKeys.skillsEnabled) private var skillsEnabled = true
    @AppStorage(SettingsKeys.openaiBaseURL) private var baseURL = "https://api.openai.com/v1"
    @AppStorage(SettingsKeys.chatModel) private var chatModel = "gpt-5.4-mini"
    @AppStorage(SettingsKeys.customPolishRules) private var customRules = ""
    @State private var apiKey = KeychainHelper.loadAPIKey() ?? ""
    @State private var keySaved = (KeychainHelper.loadAPIKey() != nil)
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Picker("润色档位：", selection: $polishLevel) {
                    ForEach(PolishLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("「仅识别」完全不联网；「标准润色」忠实于原话；「深度润色」会像 Typeless 那样重组逻辑、合并车轱辘话、必要时分段列点。菜单栏图标里可以快速切换。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("智能档位：按当前应用自动选择", isOn: $smartLevel)
                Text("聊天应用（微信/QQ/Slack/钉钉/飞书等）→ 标准润色；邮件/文档（Mail/Word/Notes/Notion 等）→ 深度润色；代码编辑器/终端 → 仅识别；其余应用 → 上面手动选的档位。注意：手动选「仅识别」时智能档位不生效，保证完全不联网。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("语音技能（V3 实验）", isOn: $skillsEnabled)
                Text("意图靠手势区分，永不误判：轻点快捷键 = 纯语音输入，说什么打什么；按住快捷键说话、松手执行 = 指令模式——选中文字后按住说「改正式一点 / 翻译成英文」直接替换选区；选中对方消息后按住说「帮我回复，就说我周五有空」，草稿复制到剪贴板。（触发方式为「按住说话」时暂无指令手势）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                SecureField("OpenAI API Key（sk-…）", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存 Key 到钥匙串") {
                        KeychainHelper.saveAPIKey(apiKey)
                        keySaved = (KeychainHelper.loadAPIKey() != nil)
                        testResult = keySaved ? "已保存 ✓" : "已清空"
                    }
                    if keySaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    Spacer()
                    Button(testing ? "测试中…" : "测试连接") {
                        testing = true
                        testResult = ""
                        KeychainHelper.saveAPIKey(apiKey)
                        keySaved = (KeychainHelper.loadAPIKey() != nil)
                        PolishService.test { _, message in
                            testing = false
                            testResult = message
                        }
                    }
                    .disabled(testing)
                }
                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                Text("默认 https://api.openai.com/v1。也可以填任何 OpenAI 兼容接口（中转、代理等）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("模型名（如 gpt-5.4-mini）", text: $chatModel)
                    .textFieldStyle(.roundedBorder)
                Text("默认 gpt-5.4-mini（质量与速度均衡）。追求极致速度可换 gpt-5.4-nano，追求深度重组质量可换 gpt-5.5。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义润色规则（可选）：")
                    TextEditor(text: $customRules)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    Text("例如：「邮件场景用正式语气」「英文术语保留原文不翻译」「数字用阿拉伯数字」。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

// MARK: - 关于

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("VoiceFlow")
                .font(.title2.bold())
            Text("版本 3.0.0-lab · Qwen3-ASR 引擎 + 语音技能")
                .foregroundColor(.secondary)
            Text("本地 Qwen3-ASR 语音识别 + GPT 智能润色\n在任何应用里，按下快捷键开口说话，松手即得到一段干净的文字。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)
            Divider().padding(.horizontal, 60)
            VStack(spacing: 4) {
                Text("隐私：录音和语音识别完全在本机进行。")
                Text("只有开启 AI 润色时，识别出的文本会发送给你配置的大模型接口。")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
