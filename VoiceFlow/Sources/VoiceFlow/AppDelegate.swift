import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let dictation = DictationController()
    private let hotkeys = HotkeyManager()
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        dictation.onPhaseChange = { [weak self] phase in
            self?.updateIcon(for: phase)
            self?.hotkeys.setRecordingActive(phase == .recording)
        }
        dictation.onNeedSettings = {
            SettingsWindowController.shared.show()
        }

        hotkeys.onTapToggle = { [weak self] in self?.dictation.toggle() }
        hotkeys.onHoldStart = { [weak self] in self?.dictation.holdStart() }
        hotkeys.onHoldEnd = { [weak self] in self?.dictation.holdEnd() }
        hotkeys.onSkillStart = { [weak self] in self?.dictation.skillHoldStart() }
        hotkeys.onSkillEnd = { [weak self] in self?.dictation.skillHoldEnd() }
        hotkeys.onCancel = { [weak self] in self?.dictation.cancel() }
        hotkeys.isRecording = { [weak self] in self?.dictation.isRecording ?? false }
        hotkeys.start()

        // 首次启动：申请辅助功能权限；模型缺失则打开设置引导下载
        if !Permissions.isAccessibilityTrusted {
            Permissions.promptAccessibility()
        }
        if QwenEngine.shared.isModelAvailable {
            // 后台预加载模型，第一次听写不用等
            QwenEngine.shared.preload()
        } else {
            SettingsWindowController.shared.show()
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(for: .idle)
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateIcon(for phase: DictationController.Phase) {
        guard let button = statusItem.button else { return }
        switch phase {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoiceFlow")
            button.contentTintColor = nil
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "录音中")
            button.contentTintColor = .systemRed
        case .processing:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "处理中")
            button.contentTintColor = .systemOrange
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hotkeyName = Settings.shared.hotkey.shortSymbol
        let modeHint = Settings.shared.triggerMode == .toggle ? "轻点 \(hotkeyName) 开始/结束听写" : "按住 \(hotkeyName) 说话"
        let titleItem = NSMenuItem(title: modeHint, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        switch dictation.phase {
        case .idle:
            menu.addItem(makeItem("开始听写", #selector(toggleDictation)))
        case .recording:
            menu.addItem(makeItem("停止并输出", #selector(toggleDictation)))
            menu.addItem(makeItem("取消录音（Esc）", #selector(cancelDictation)))
        case .processing:
            let item = NSMenuItem(title: "处理中…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 润色档位
        let levelItem = NSMenuItem(title: "润色档位", action: nil, keyEquivalent: "")
        let levelMenu = NSMenu()
        let current = Settings.shared.polishLevel
        for level in PolishLevel.allCases {
            let mi = NSMenuItem(title: level.displayName, action: #selector(setPolishLevel(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = level.rawValue
            mi.state = (level == current) ? .on : .off
            levelMenu.addItem(mi)
        }
        levelItem.submenu = levelMenu
        menu.addItem(levelItem)

        // 历史记录
        let historyItem = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let items = HistoryStore.shared.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "（暂无）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for item in items.prefix(10) {
                var title = item.polished.replacingOccurrences(of: "\n", with: " ")
                if title.count > 36 {
                    title = String(title.prefix(36)) + "…"
                }
                let mi = NSMenuItem(title: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.polished
                mi.toolTip = "点击复制全文"
                historyMenu.addItem(mi)
            }
            historyMenu.addItem(.separator())
            historyMenu.addItem(makeItem("清空记录", #selector(clearHistory)))
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())

        if QwenEngine.shared.isModelLoaded {
            menu.addItem(makeItem("释放模型内存", #selector(unloadModel)))
        }

        let settingsItem = makeItem("设置…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = makeItem("退出 VoiceFlow", #selector(quit))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 动作

    @objc private func toggleDictation() {
        dictation.toggle()
    }

    @objc private func cancelDictation() {
        dictation.cancel()
    }

    @objc private func setPolishLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = PolishLevel(rawValue: raw) else { return }
        Settings.shared.polishLevel = level
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func clearHistory() {
        HistoryStore.shared.clear()
    }

    @objc private func unloadModel() {
        QwenEngine.shared.unloadModel()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
