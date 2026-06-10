import AppKit
import SwiftUI

// MARK: - 悬浮窗状态

final class OverlayState: ObservableObject {
    enum Mode: Equatable {
        case recording
        case processing(String)
        case success(String)
        case error(String)
    }

    @Published var mode: Mode = .recording
    @Published var levels: [Float] = Array(repeating: 0.05, count: 13)

    func pushLevel(_ level: Float) {
        var l = levels
        l.removeFirst()
        l.append(max(0.05, min(1.0, level)))
        levels = l
    }

    func resetLevels() {
        levels = Array(repeating: 0.05, count: 13)
    }
}

// MARK: - 悬浮窗视图

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 10) {
            switch state.mode {
            case .recording:
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<state.levels.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 3, height: 5 + 23 * CGFloat(state.levels[i]))
                    }
                }
                .animation(.linear(duration: 0.1), value: state.levels)
                Text("正在听…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            case .processing(let label):
                ProgressView()
                    .controlSize(.small)
                    .colorInvert()
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            case .success(let label):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            case .error(let label):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minWidth: 160, minHeight: 44)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        )
        .padding(16)
    }
}

// MARK: - 悬浮窗控制器

final class OverlayController {

    let state = OverlayState()
    private var panel: NSPanel?
    private var hideGeneration = 0

    private func ensurePanel() -> NSPanel {
        if let p = panel { return p }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 90),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: OverlayContainer(state: state))
        hosting.frame = p.contentRect(forFrameRect: p.frame)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        panel = p
        return p
    }

    private func position(_ p: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - p.frame.width / 2
        let y = frame.minY + 28
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showRecording() {
        hideGeneration += 1
        state.resetLevels()
        state.mode = .recording
        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
    }

    func showProcessing(_ label: String) {
        hideGeneration += 1
        state.mode = .processing(label)
        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
    }

    func flashSuccess(_ label: String) {
        flash(.success(label), duration: 1.0)
    }

    func flashError(_ label: String) {
        flash(.error(label), duration: 2.5)
    }

    private func flash(_ mode: OverlayState.Mode, duration: Double) {
        hideGeneration += 1
        let generation = hideGeneration
        state.mode = mode
        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.hideGeneration == generation else { return }
            self.hide()
        }
    }

    func hide() {
        hideGeneration += 1
        panel?.orderOut(nil)
    }
}

/// 让胶囊在固定大小面板里居中
private struct OverlayContainer: View {
    @ObservedObject var state: OverlayState
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                OverlayView(state: state)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }
}
