import AppKit

/// 把文字插入到当前光标处：写入剪贴板 → 模拟 ⌘V → 恢复原剪贴板。
/// 设计原则：宁可让用户多按一次 ⌘V，也绝不让文字消失。
enum TextInserter {

    enum Outcome {
        case pasted          // 已粘贴到目标
        case clipboardOnly   // 没把握粘贴成功，文本保留在剪贴板里
    }

    /// targetBundleID：录音开始时的目标应用。
    /// 如果用户在识别/润色期间切走了窗口，先把目标应用拉回前台、确认到位后再粘贴；
    /// 拉不回来就把文本留在剪贴板并告知用户。completion 在主线程回调。
    static func insert(_ text: String, targetBundleID: String = "",
                       allowClipboardRestore: Bool = true,
                       conservativePaste: Bool = false,
                       completion: @escaping (Outcome) -> Void) {
        guard Permissions.isAccessibilityTrusted else {
            putOnClipboard(text)
            completion(.clipboardOnly)
            return
        }

        guard !targetBundleID.isEmpty else {
            pasteIntoCurrentFocus(text, allowRestore: allowClipboardRestore,
                                  conservativePaste: conservativePaste, completion: completion)
            return
        }

        // 无论当前 frontmost 是否匹配，都重新激活目标 App。
        // App 启动后的第一次粘贴最容易出现"App 在前台但输入框还没吃键"。
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: targetBundleID).first else {
            putOnClipboard(text)
            completion(.clipboardOnly)
            return
        }
        app.activate(options: [.activateAllWindows])
        waitForFrontmost(targetBundleID, attemptsLeft: conservativePaste ? 16 : 8) { arrived in
            if arrived {
                pasteIntoCurrentFocus(text, allowRestore: allowClipboardRestore,
                                      conservativePaste: conservativePaste, completion: completion)
            } else {
                putOnClipboard(text)
                completion(.clipboardOnly)
            }
        }
    }

    /// 轮询等待目标应用到达前台（每 0.15s 一次，最多约 1.2s）
    private static func waitForFrontmost(_ bundleID: String, attemptsLeft: Int,
                                         completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            completion(true)
            return
        }
        guard attemptsLeft > 0 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            waitForFrontmost(bundleID, attemptsLeft: attemptsLeft - 1, completion: completion)
        }
    }

    private static func putOnClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func pasteIntoCurrentFocus(_ text: String, allowRestore: Bool,
                                              conservativePaste: Bool,
                                              completion: @escaping (Outcome) -> Void) {
        let focusDelay = conservativePaste ? 0.75 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            performPaste(text, allowRestore: allowRestore, conservativePaste: conservativePaste) {
                completion(.pasted)
            }
        }
    }

    private static func performPaste(_ text: String, allowRestore: Bool,
                                     conservativePaste: Bool = false,
                                     completion: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 给剪贴板写入留一点时间，再发送 ⌘V
        let pasteDelay = conservativePaste ? 0.35 : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            sendCmdV(keyHold: conservativePaste ? 0.12 : 0.03) {
                completion?()
            }
            if allowRestore && Settings.shared.restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    // 只有当剪贴板还是我们写入的内容时才恢复，避免覆盖用户新复制的东西
                    if pasteboard.string(forType: .string) == text {
                        pasteboard.clearContents()
                        if let old = oldString {
                            pasteboard.setString(old, forType: .string)
                        }
                    }
                }
            }
        }
    }

    private static func sendCmdV(keyHold: Double = 0.03, completion: (() -> Void)? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        // 9 = kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            completion?()
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHold) {
            keyUp.post(tap: .cghidEventTap)
            completion?()
        }
    }

}
