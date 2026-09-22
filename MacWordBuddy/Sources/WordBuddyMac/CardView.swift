import SwiftUI
import AppKit
import ApplicationServices

// 悬浮卡片 UI，与 Windows 版 MainWindow.cs 完全对等
struct CardView: View {
    @ObservedObject var vm: MainViewModel
    var t: ThemePalette { vm.t }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 8) {
                Text("字")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("字数小助手")
                    .font(.system(size: 12))
                    .foregroundStyle(t.textSecondary)
                Spacer()
                Button {
                    vm.panel?.performMiniaturize(nil)
                } label: {
                    Text("—").font(.system(size: 11)).foregroundStyle(t.textSecondary)
                        .frame(width: 36, height: 28)
                }.buttonStyle(.plain)
                Button {
                    vm.panel?.close()
                } label: {
                    Text("✕").font(.system(size: 11)).foregroundStyle(t.textSecondary)
                        .frame(width: 36, height: 28)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 28)

            // 模式行
            HStack {
                Text(vm.modeLabel).font(.system(size: 11)).foregroundStyle(t.textTertiary)
                Spacer()
                Text("目标 \(vm.target)").font(.system(size: 11)).foregroundStyle(t.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // 大数字 + 稿费
            HStack(alignment: .bottom, spacing: 0) {
                Spacer()
                Text(vm.displayCount)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(vm.displayColor)
                    .animation(.easeOut(duration: 0.18), value: vm.displayCount)
                Spacer()
                Text(vm.payText)
                    .font(.system(size: 18))
                    .foregroundStyle(t.textSecondary)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(t.progressTrack)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(vm.progressColor)
                        .frame(width: max(0, geo.size.width * vm.progressRatio), height: 6)
                        .animation(.easeOut(duration: 0.18), value: vm.progressRatio)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 10)

            // 按钮行
            HStack(spacing: 8) {
                Button { vm.togglePause() } label: {
                    Text(vm.paused ? "继续" : "计数中")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.accentText)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.accent))
                }.buttonStyle(.plain)

                Button { vm.resetClicked() } label: {
                    Text("重置")
                        .font(.system(size: 12))
                        .foregroundStyle(t.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.secondaryBtn))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.stroke, lineWidth: 1))
                }.buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text(vm.flashOrCumRounds).font(.system(size: 11)).foregroundStyle(t.textTertiary)
                    Text(vm.cumCharsText).font(.system(size: 11)).foregroundStyle(t.textTertiary)
                }
                .frame(maxWidth: .infinity)

                Button { vm.openSettings() } label: {
                    Text("设置")
                        .font(.system(size: 12))
                        .foregroundStyle(t.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.secondaryBtn))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.stroke, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(t.card.opacity(t.cardTranslucent ? 0.82 : 1.0))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(t.isDark ? 0.35 : 0.2), radius: 8, y: 1)
        )
    }
}

// 状态与业务逻辑集中在此，供卡片与设置窗共享
@MainActor
final class MainViewModel: ObservableObject {
    @Published var sessionCount = 0
    @Published var paused = false
    @Published var cumRounds: Int
    @Published var cumChars: Int
    @Published var flashMsg = ""
    @Published var celebrated = false
    @Published var hint = ""
    @Published var settingsVersion = 0   // 设置变更后 +1 触发 UI 刷新

    var settings: AppSettings
    weak var panel: NSPanel?
    var settingsPanel: NSPanel?

    private var lastCreditedRounds = 0
    private var flashUntil = Date.distantPast
    private var uiTimer: Timer?
    let monitor = MacTextMonitor.shared

    init(settings: AppSettings) {
        self.settings = settings
        cumRounds = max(0, settings.CumulativeRounds)
        cumChars = max(0, settings.CumulativeChars)
        lastCreditedRounds = 0 // 与 Windows 版一致：会话启动不补记
    }

    var t: ThemePalette { ThemePalette.forTheme(settings.Theme) }

    var target: Int { max(1, settings.Target) }
    var isDown: Bool { settings.Mode.caseInsensitiveCompare("down") == .orderedSame }

    var displayCount: String {
        isDown ? String(max(0, target - sessionCount)) : String(sessionCount)
    }
    var displayColor: Color {
        (sessionCount >= target) ? t.success : t.textPrimary
    }
    var modeLabel: String { isDown ? "倒数模式" : "累计模式" }
    var progressRatio: Double {
        if isDown { return 1.0 - Double(min(sessionCount, target)) / Double(target) }
        return min(1.0, Double(sessionCount) / Double(target))
    }
    var progressColor: Color { (sessionCount >= target) ? t.success : t.accent }

    var payText: String {
        let v = Double(sessionCount) / 1000.0 * max(0, settings.YuanPerThousand)
        let s = abs(v - v.rounded()) < 0.0001 ? String(format: "%.0f", v) : String(format: "%.2f", v).trimmingZeros
        return "稿费：\(s) 元"
    }

    var cumCharsText: String { "累计字数：\(cumChars) 字" }

    var flashOrCumRounds: String {
        if !flashMsg.isEmpty && Date() < flashUntil { return flashMsg }
        return "累计达成：\(cumRounds) 轮"
    }

    func start() {
        monitor.onCountChanged = { [weak self] delta, total in
            Task { @MainActor in
                guard let self else { return }
                self.sessionCount = total
                self.creditRoundsIfNeeded()
                if total >= self.target && !self.celebrated {
                    self.celebrated = true
                    NSSound.beep()
                    self.flash("目标达成！")
                } else if total < self.target {
                    self.celebrated = false
                }
            }
        }
        monitor.onHintChanged = { [weak self] h in
            Task { @MainActor in self?.hint = h }
        }
        if !monitor.start() {
            flash(hint == "no_permission" || !AXIsProcessTrusted() ? "请授予辅助功能权限" : "监听启动失败")
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        sessionCount = monitor.SessionCount
    }

    func tick() {
        // 刷新 flash 过期（SwiftUI 依赖 @Published，这里手动触发）
        if !flashMsg.isEmpty && Date() >= flashUntil {
            flashMsg = ""
            objectWillChange.send()
        }
    }

    func flash(_ msg: String) {
        flashMsg = msg
        flashUntil = Date().addingTimeInterval(1.8)
        objectWillChange.send()
    }

    private func creditRoundsIfNeeded() {
        guard settings.CumulativeEnabled else { return }
        let rounds = sessionCount / target
        if rounds > lastCreditedRounds {
            let gained = rounds - lastCreditedRounds
            cumRounds += gained
            cumChars += gained * target
            settings.CumulativeRounds = cumRounds
            settings.CumulativeChars = cumChars
            settings.save()
        }
        lastCreditedRounds = max(lastCreditedRounds, rounds)
    }

    func togglePause() {
        paused.toggle()
        monitor.pause(paused)
        flash(paused ? "已暂停" : "已继续计数")
    }

    func resetClicked() {
        if sessionCount > 0 {
            monitor.resetSession()
            sessionCount = 0
            lastCreditedRounds = 0
            celebrated = false
            flash("本节已重置")
        } else {
            showClearCumulativeDialog()
        }
    }

    func clearCumulative() {
        cumRounds = 0
        cumChars = 0
        lastCreditedRounds = 0
        settings.CumulativeRounds = 0
        settings.CumulativeChars = 0
        settings.save()
        flashMsg = ""
        celebrated = false
        objectWillChange.send()
    }

    func openSettings() {
        if let p = settingsPanel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        let panel = SettingsPanelController(vm: self).panel
        settingsPanel = panel
        panel?.makeKeyAndOrderFront(nil)
    }

    // 设置应用后刷新
    func applySettings(_ s: AppSettings) {
        settings = s
        settings.save()
        settingsVersion += 1
        panel?.alphaValue = s.Opacity
        panel?.level = s.AlwaysOnTop ? .floating : .normal
        celebrated = false
        flash("已保存设置")
    }

    func selfTest() {
        monitor.debugAdd(5)
        flash("已模拟 +5 字")
    }

    // 二次确认弹窗（对应 ShowClearCumulativeDialog）
    func showClearCumulativeDialog() {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = "清空累计数据？"
        alert.informativeText = "再次点击将清空累计数据（累计达成 / 累计字数），确定吗？"
        alert.addButton(withTitle: "是")
        alert.addButton(withTitle: "否")
        alert.beginSheetModal(for: panel) { resp in
            if resp == .alertFirstButtonReturn { self.clearCumulative() }
        }
    }
}

extension String {
    var trimmingZeros: String {
        var s = self
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// 悬浮面板：无边框、置顶、可拖动、非激活（对应 MainWindow 的 WindowStyle.None + Topmost）
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
}

final class PanelController {
    let panel: NSPanel
    let vm: MainViewModel

    init(settings: AppSettings, vm: MainViewModel) {
        self.vm = vm
        let size = NSSize(width: 360, height: 210)
        let frame: NSRect
        if let l = settings.Left, let tp = settings.Top {
            frame = NSRect(origin: NSPoint(x: l, y: tp), size: size)
        } else {
            if let screen = NSScreen.main {
                let v = screen.visibleFrame
                frame = NSRect(x: v.maxX - 360 - 28, y: v.minY + 72, width: 360, height: 210)
            } else {
                frame = NSRect(x: 100, y: 100, width: 360, height: 210)
            }
        }
        panel = FloatingPanel(contentRect: frame)
        panel.alphaValue = settings.Opacity
        vm.panel = panel

        let root = CardView(vm: vm)
        let host = NSHostingView(rootView: root)
        panel.contentView = host

        // 关闭时保存位置
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            let f = self.panel.frame
            self.vm.settings.Left = Double(f.origin.x)
            self.vm.settings.Top = Double(f.origin.y)
            self.vm.settings.save()
        }
    }
}
