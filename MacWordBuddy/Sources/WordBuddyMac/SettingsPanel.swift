import SwiftUI
import AppKit

// 设置面板，与 Windows 版 SettingsWindow.cs 项一一对应
struct SettingsPanelView: View {
    @ObservedObject var vm: MainViewModel
    @State private var targetText: String
    @State private var rateText: String
    @State private var modeUp: Bool
    @State private var theme: String
    @State private var topmost: Bool
    @State private var cumulative: Bool
    @State private var opacity: Double

    init(vm: MainViewModel) {
        self.vm = vm
        let s = vm.settings
        _targetText = State(initialValue: String(s.Target))
        _rateText = State(initialValue: String(format: "%.2f", s.YuanPerThousand).trimmingZeros)
        _modeUp = State(initialValue: s.Mode.caseInsensitiveCompare("down") != .orderedSame)
        _theme = State(initialValue: s.Theme)
        _topmost = State(initialValue: s.AlwaysOnTop)
        _cumulative = State(initialValue: s.CumulativeEnabled)
        _opacity = State(initialValue: s.Opacity)
    }

    var t: ThemePalette { vm.t }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.textPrimary)

            Text("目标字数").font(.system(size: 11)).foregroundStyle(t.textTertiary)
            TextField("300", text: $targetText)
                .textFieldStyle(.roundedBorder)

            Text("每千字单价（元）").font(.system(size: 11)).foregroundStyle(t.textTertiary)
            TextField("50", text: $rateText)
                .textFieldStyle(.roundedBorder)

            Text("计数模式").font(.system(size: 11)).foregroundStyle(t.textTertiary)
            Picker("", selection: $modeUp) {
                Text("累计（0 → 目标）").tag(true)
                Text("倒数（目标 → 0）").tag(false)
            }.pickerStyle(.radio)

            Text("主题").font(.system(size: 11)).foregroundStyle(t.textTertiary)
            Picker("", selection: $theme) {
                Text("深色").tag("dark")
                Text("浅色半透明").tag("light")
                Text("纯白").tag("pure")
            }.pickerStyle(.radio)

            Toggle("窗口置顶", isOn: $topmost)
                .font(.system(size: 12)).foregroundStyle(t.textPrimary)
            Toggle("累计统计（每完成一轮目标累计）", isOn: $cumulative)
                .font(.system(size: 12)).foregroundStyle(t.textPrimary)

            HStack {
                Text("窗口透明度").font(.system(size: 12)).foregroundStyle(t.textPrimary)
                Slider(value: $opacity, in: 0.7...1.0)
                Text("\(Int(round(opacity * 100)))%")
                    .font(.system(size: 11)).foregroundStyle(t.textSecondary).frame(width: 40)
            }

            HStack {
                Button("自测 +5 字") { vm.selfTest() }
                Spacer()
                Button("取消") { closeSelf() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 340)
        .background(t.card)
    }

    private func save() {
        var s = vm.settings
        s.Target = Int(targetText) ?? s.Target
        s.YuanPerThousand = Double(rateText) ?? s.YuanPerThousand
        s.Mode = modeUp ? "up" : "down"
        s.Theme = theme
        s.AlwaysOnTop = topmost
        s.CumulativeEnabled = cumulative
        s.Opacity = opacity
        vm.applySettings(s)
        closeSelf()
    }

    private func closeSelf() {
        vm.settingsPanel?.orderOut(nil)
    }
}

final class SettingsPanelController {
    let panel: NSPanel

    init(vm: MainViewModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                        styleMask: [.titled, .closable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.title = "设置"
        panel.isFloatingPanel = true
        panel.center()
        panel.contentView = NSHostingView(rootView: SettingsPanelView(vm: vm))
    }
}
