import AppKit
import ApplicationServices

// 权限引导：无辅助功能权限时弹授权请求并提示
enum PermissionGuide {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// 入口：无 Dock 图标的常驻应用（对应 Program.cs）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 不占 Dock
app.run()
