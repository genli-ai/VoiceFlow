import AppKit
import ApplicationServices

/// 读取当前焦点元素的选中文本（纯辅助功能 API，不碰剪贴板）。
/// 读不到就返回 nil——技能路由会自动降级为普通输入，绝不误伤。
enum SelectionReader {

    static func readSelectedText() -> String? {
        guard Permissions.isAccessibilityTrusted else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedObj) == .success,
              let focusedRef = focusedObj else {
            return nil
        }
        let element = focusedRef as! AXUIElement

        var selectionObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextAttribute as CFString,
                                            &selectionObj) == .success,
              let text = selectionObj as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    /// 异步读取选区：先试 AX；失败则模拟 ⌘C 兜底（保存并恢复原剪贴板）。
    /// 适用于微信/QQ 等无障碍接口残缺的应用。completion 在主线程回调。
    static func readSelectedTextWithClipboardFallback(completion: @escaping (String?) -> Void) {
        if let text = readSelectedText() {
            DispatchQueue.main.async { completion(text) }
            return
        }
        guard Permissions.isAccessibilityTrusted else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        let oldCount = pb.changeCount

        sendCmdC()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var result: String? = nil
            if pb.changeCount != oldCount,
               let copied = pb.string(forType: .string),
               !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = copied
            }
            // 恢复原剪贴板，不留痕迹
            if pb.changeCount != oldCount {
                pb.clearContents()
                if let old = oldString {
                    pb.setString(old, forType: .string)
                }
            }
            completion(result)
        }
    }

    private static func sendCmdC() {
        let source = CGEventSource(stateID: .hidSystemState)
        // 8 = kVK_ANSI_C
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
