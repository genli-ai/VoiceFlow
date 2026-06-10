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
                       completion: @escaping (Outcome) -> Void) {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // 焦点没动过：正常粘贴
        if targetBundleID.isEmpty || frontID == targetBundleID {
            performPaste(text, allowRestore: allowClipboardRestore) {
                completion(.pasted)
            }
            return
        }

        // 焦点切走了：尝试把目标应用拉回前台
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: targetBundleID).first else {
            putOnClipboard(text)
            completion(.clipboardOnly)
            return
        }
        app.activate(options: [])
        waitForFrontmost(targetBundleID, attemptsLeft: 8) { arrived in
            if arrived {
                // 等一拍让焦点真正落到输入框，再粘贴；
                // 风险路径不恢复剪贴板，万一没粘上用户还能 ⌘V
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    performPaste(text, allowRestore: false) {
                        completion(.pasted)
                    }
                }
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

    private static func performPaste(_ text: String, allowRestore: Bool,
                                     completion: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 给剪贴板写入留一点时间，再发送 ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            sendCmdV {
                completion?()
            }
            if allowRestore && Settings.shared.restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
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

    private static func sendCmdV(completion: (() -> Void)? = nil) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 9 = kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            completion?()
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            keyUp.post(tap: .cghidEventTap)
            completion?()
        }
    }
}
