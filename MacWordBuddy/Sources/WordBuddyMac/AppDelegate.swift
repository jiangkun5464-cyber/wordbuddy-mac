import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var vm: MainViewModel?
    var panelController: PanelController?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.load()
        let vm = MainViewModel(settings: settings)
        self.vm = vm

        // 悬浮卡片
        let pc = PanelController(settings: settings, vm: vm)
        panelController = pc
        pc.panel.makeKeyAndOrderFront(nil)

        // 菜单栏图标（退出入口）
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "字"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示窗口", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item

        if !PermissionGuide.isTrusted {
            PermissionGuide.prompt()
        }
        vm.start()
    }

    @objc func showPanel() {
        panelController?.panel.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() {
        // 保存窗口位置
        if let p = panelController?.panel {
            let f = p.frame
            vm?.settings.Left = Double(f.origin.x)
            vm?.settings.Top = Double(f.origin.y)
            vm?.settings.save()
        }
        MacTextMonitor.shared.stop()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MacTextMonitor.shared.stop()
    }
}
