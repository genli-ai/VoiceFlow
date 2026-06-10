import AppKit

/// 全局热键监听。
/// 切换模式：单独"轻点"所选修饰键（按下到松开 < 0.6s 且期间没按其它键）即触发开始/结束；
/// 按住模式：按下开始，松开结束。
/// 录音中按 Esc 取消。
final class HotkeyManager {

    var onTapToggle: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    /// 轻点触发模式下：按住 0.6s 进入"指令模式"录音，松开结束（V3 语音技能）
    var onSkillStart: (() -> Void)?
    var onSkillEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 由控制器提供：当前是否正在录音
    var isRecording: (() -> Bool) = { false }

    private var monitors: [Any] = []
    private var pressedAt: Date?
    var tapCandidate = false
    private var holdWorkItem: DispatchWorkItem?
    private var skillActive = false

    // 录音期间的 Esc 拦截（CGEventTap，普通按键的全局监听在新版 macOS 上不可靠）
    private var escTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?

    private let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    func start() {
        stop()
        let m1 = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        let m2 = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        let m3 = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        let m4 = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
        monitors = [m1, m2, m3, m4].compactMap { $0 }
    }

    func stop() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors = []
        stopEscTap()
    }

    /// 录音开始/结束时由外部调用：录音期间启用 Esc 拦截
    func setRecordingActive(_ active: Bool) {
        if active {
            startEscTap()
        } else {
            stopEscTap()
        }
    }

    private func startEscTap() {
        guard escTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { manager.reenableEscTap() }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 53 {
                    DispatchQueue.main.async {
                        if manager.isRecording() { manager.onCancel?() }
                    }
                    return nil  // 吃掉这次 Esc，不传给前台应用
                }
                DispatchQueue.main.async { manager.tapCandidate = false }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: refcon) else {
            return  // 创建失败（权限不足）时退回 NSEvent 监听
        }
        escTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        escRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func reenableEscTap() {
        if let tap = escTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func stopEscTap() {
        if let tap = escTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = escRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        escTap = nil
        escRunLoopSource = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let choice = Settings.shared.hotkey
        let mode = Settings.shared.triggerMode

        guard event.keyCode == choice.keyCode else {
            // 按了别的修饰键，取消"轻点"判定
            tapCandidate = false
            return
        }

        let flags = event.modifierFlags.intersection(relevantFlags)
        let targetFlag = NSEvent.ModifierFlags(rawValue: choice.flagMask)
        let isDown = flags.contains(targetFlag)

        switch mode {
        case .toggle:
            if isDown {
                // 必须是"只按了这一个修饰键"才算候选
                if flags == targetFlag {
                    tapCandidate = true
                    pressedAt = Date()
                    // 按住 0.6s 且当前空闲 → 进入指令模式录音
                    holdWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.tapCandidate, !self.isRecording() else { return }
                        self.skillActive = true
                        self.onSkillStart?()
                    }
                    holdWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                } else {
                    tapCandidate = false
                    holdWorkItem?.cancel()
                }
            } else {
                holdWorkItem?.cancel()
                if skillActive {
                    skillActive = false
                    DispatchQueue.main.async { [weak self] in self?.onSkillEnd?() }
                } else if tapCandidate, let t = pressedAt, Date().timeIntervalSince(t) < 0.6 {
                    DispatchQueue.main.async { [weak self] in self?.onTapToggle?() }
                }
                tapCandidate = false
                pressedAt = nil
            }
        case .hold:
            if isDown {
                if flags == targetFlag, pressedAt == nil {
                    pressedAt = Date()
                    DispatchQueue.main.async { [weak self] in self?.onHoldStart?() }
                }
            } else {
                if pressedAt != nil {
                    pressedAt = nil
                    DispatchQueue.main.async { [weak self] in self?.onHoldEnd?() }
                }
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // 修饰键按住期间敲了别的键（快捷键等）→ 不算轻点，也不进指令模式
        tapCandidate = false
        holdWorkItem?.cancel()
        // Esc 取消录音
        if event.keyCode == 53, isRecording() {
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
        }
    }
}
