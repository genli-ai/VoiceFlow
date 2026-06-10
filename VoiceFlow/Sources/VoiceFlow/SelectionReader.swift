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
}
