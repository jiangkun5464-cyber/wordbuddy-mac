import AppKit
import ApplicationServices

// 纯函数 diff 逻辑（可单测）：统计 baseline -> current 新增的“文本元素”数
enum CountDiff {
    static func insertedRange(baseline: String, current: String) -> String {
        if current.hasPrefix(baseline) { return String(current.dropFirst(baseline.count)) }
        if baseline.hasPrefix(current) { return "" } // 纯删除
        // 求最长公共前缀
        let b = Array(baseline), c = Array(current)
        var p = 0
        while p < b.count && p < c.count && b[p] == c[p] { p += 1 }
        // 求最长公共后缀（不超过前缀之后的部分）
        var s = 0
        while s < b.count - p && s < c.count - p && b[b.count - 1 - s] == c[c.count - 1 - s] { s += 1 }
        let newMid = c[(p)..<(c.count - s)]
        return String(newMid)
    }

    // 按“文本元素”计（兼容 emoji / 生僻字代理对），与 Windows 版 CountTyped 对等
    static func countGraphemes(_ text: String) -> Int {
        var n = 0
        var iter = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        func isEmojiBase(_ s: Unicode.Scalar) -> Bool {
            return s.value >= 0x1F300 || (s.properties.isEmoji && s.value > 0x2600)
        }
        var scalars: [Unicode.Scalar] = []
        while let s = iter.next() { scalars.append(s) }
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s.value == 0x200D || isEmojiBase(s) || (s.value >= 0xFE00 && s.value <= 0xFE0F) || s.value == 0x20E3 {
                // 属于 emoji 组合序列，继续吞并
                var j = i + 1
                while j < scalars.count {
                    let t = scalars[j]
                    if t.value == 0x200D || isEmojiBase(t) || (t.value >= 0xFE00 && t.value <= 0xFE0F) || t.value == 0x20E3 || t.value == 0x20D9 {
                        j += 1
                    } else { break }
                }
                if j > i + 1 { n += 1; i = j; pending = nil; continue }
                // 单个 emoji base 也算一个字
                n += 1; i += 1; continue
            }
            if s.properties.isWhitespace { i += 1; continue }
            n += 1
            i += 1
        }
        _ = pending
        return n
    }

    static func countInserted(baseline: String, current: String) -> Int {
        let inserted = insertedRange(baseline: baseline, current: current)
        if inserted.isEmpty { return 0 }
        return countGraphemes(inserted)
    }
}

// macOS 核心计数器：CGEventTap（按键状态机）+ AX 轮询（文本 diff）
// 对应 Windows 版 TypingMonitor.cs
final class MacTextMonitor {
    static let shared = MacTextMonitor()

    private let lock = NSLock()
    private var sessionCount = 0
    private var paused = false
    private var running = false

    // 组字会话状态
    private var composing = false           // 检测到普通按键 -> 会话进行中
    private var baseline = ""               // 会话开始时的文本快照
    private var baselineValid = false
    private var lastKeyEventAt = Date.distantPast
    private var pasteUntil = Date.distantPast   // ⌘V 之后短窗口内的插入视为粘贴
    private var lastAXChangeAt = Date.distantPast
    private var ownPid = ProcessInfo.processInfo.processIdentifier

    // AX 轮询
    private var pollTimer: DispatchSourceTimer?
    private let systemWide = AXUIElementCreateSystemWide()
    private var lastFocused: AXUIElement?
    private var axHint = ""

    var onCountChanged: ((Int, Int) -> Void)?       // (delta, total)
    var onHintChanged: ((String) -> Void)?

    var SessionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return sessionCount
    }
    var IsPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return paused
    }
    var IsRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }
    var DiagHint: String {
        lock.lock(); defer { lock.unlock() }
        return axHint
    }

    // MARK: - 启动 / 停止

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        guard AXIsProcessTrusted() else {
            setHint("no_permission")
            return false
        }
        ownPid = ProcessInfo.processInfo.processIdentifier
        guard installEventTap() else {
            setHint("eventtap_fail")
            return false
        }
        startPolling()
        lock.lock()
        running = true
        paused = false
        lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        pollTimer?.cancel()
        pollTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let rlSource = tapRunloopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), rlSource, .commonModes)
            tapRunloopSource = nil
        }
    }

    func pause(_ p: Bool = true) {
        lock.lock()
        paused = p
        if p { composing = false; baselineValid = false }
        lock.unlock()
    }

    func resetSession() {
        setCount(0)
    }

    func setSessionCount(_ n: Int) {
        setCount(max(0, n))
    }

    func debugAdd(_ n: Int) {
        add(n, source: "debug")
    }

    // MARK: - 私有

    private var eventTap: CFMachPort?
    private var tapRunloopSource: CFRunLoopSource?

    private func setCount(_ n: Int) {
        lock.lock()
        let old = sessionCount
        sessionCount = n
        lock.unlock()
        if n != old { onCountChanged?(n - old, n) }
    }

    private func add(_ delta: Int, source: String) {
        guard delta != 0 else { return }
        lock.lock()
        if paused { lock.unlock(); return }
        sessionCount = max(0, sessionCount + delta)
        let total = sessionCount
        lock.unlock()
        log("\(source) +\(delta) => \(total)")
        onCountChanged?(delta, total)
    }

    private func setHint(_ h: String) {
        lock.lock()
        axHint = h
        lock.unlock()
        onHintChanged?(h)
    }

    private func installEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                MacTextMonitor.shared.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        tapRunloopSource = source
        return true
    }

    private static let keyDelete = UInt16(51)
    private static let keyEscape = UInt16(53)
    private static let keyReturn = UInt16(36)

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }
        let flags = event.flags
        let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        lock.lock()
        lastKeyEventAt = Date()
        lock.unlock()

        if hasModifier {
            // ⌘V 粘贴：标记窗口期，之后的文本增长不计
            if flags.contains(.maskCommand), event.getIntegerValueField(.keyboardEventKeycode) == 9 {
                lock.lock()
                pasteUntil = Date().addingTimeInterval(1.0)
                composing = false
                baselineValid = false
                lock.unlock()
            }
            return // 快捷键一律不计
        }

        let keycode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch keycode {
        case Self.keyEscape:
            // 取消组字：会话作废
            lock.lock()
            composing = false
            baselineValid = false
            lock.unlock()
        case Self.keyReturn:
            commitNow(reason: "enter")
        case Self.keyDelete:
            // 回删：作废基线，等待删除后的稳定文本重建
            lock.lock()
            composing = false
            baselineValid = false
            lock.unlock()
        default:
            // 普通字符键（字母/数字/标点/空格）：进入或延续组字会话
            lock.lock()
            if !composing { baselineValid = false }
            composing = true
            lock.unlock()
        }
    }

    // 立即结算当前会话（Enter 提交时 AX 文本更新略有延迟，延后 80ms 读取）
    private func commitNow(reason: String) {
        var b = ""
        lock.lock()
        guard composing, baselineValid else {
            composing = false
            baselineValid = false
            lock.unlock()
            return
        }
        b = baseline
        composing = false
        baselineValid = false
        lock.unlock()
        let delay: TimeInterval = reason == "enter" ? 0.08 : 0
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let cur = self.readFocusedText() ?? b
            let delta = CountDiff.countInserted(baseline: b, current: cur)
            if delta > 0, Date() > self.pasteUntilSafe {
                self.add(delta, source: "commit(\(reason))")
            } else {
                self.log("commit(\(reason)) skipped delta=\(delta)")
            }
        }
    }

    private var pasteUntilSafe: Date {
        lock.lock(); defer { lock.unlock() }
        return pasteUntil
    }

    // MARK: - AX 轮询

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "WordBuddy.AXPoll"))
        timer.schedule(deadline: .now() + 0.05, repeating: 0.06)
        timer.setEventHandler { [weak self] in self?.pollOnce() }
        timer.resume()
        pollTimer = timer
    }

    private func pollOnce() {
        lock.lock()
        guard running, !paused else { lock.unlock(); return }
        let composingNow = composing
        let baselineValidNow = baselineValid
        let lastKey = lastKeyEventAt
        lock.unlock()

        guard let text = readFocusedText() else {
            setHint("no_ax")
            // 焦点丢失/应用不支持：会话作废
            lock.lock()
            composing = false
            baselineValid = false
            lock.unlock()
            return
        }

        if !composingNow {
            // 稳定期：基线 = 当前文本
            lock.lock()
            baseline = text
            baselineValid = true
            lock.unlock()
            setHint("idle")
            return
        }

        // 会话进行中
        if !baselineValidNow {
            lock.lock()
            baseline = text
            baselineValid = true
            lock.unlock()
            setHint("comp:start")
            return
        }

        // 提交判定 1：插入内容包含 CJK（中文上屏）
        lock.lock()
        let b = baseline
        lock.unlock()
        let inserted = CountDiff.insertedRange(baseline: b, current: text)
        let hasCJK = inserted.unicodeScalars.contains { c in
            (c.value >= 0x4E00 && c.value <= 0x9FFF)
                || (c.value >= 0x3400 && c.value <= 0x4DBF)
                || (c.value >= 0x3000 && c.value <= 0x303F)   // CJK 标点
                || (c.value >= 0xFF00 && c.value <= 0xFFEF)   // 全角字符
        }
        // 提交判定 2：按键停歇 > 800ms（英文模式 / 英文直输结算）
        let idle = Date().timeIntervalSince(lastKey) > 0.8 && Date().timeIntervalSince(lastAXChangeAt) > 0.8

        if hasCJK {
            commitCJK(baseline: b, current: text)
        } else if idle {
            commitNow(reason: "idle")
        } else {
            setHint("comp:\(inserted.count)")
        }
    }

    private func commitCJK(baseline b: String, current: String) {
        lock.lock()
        composing = false
        baselineValid = false
        lock.unlock()
        let delta = CountDiff.countInserted(baseline: b, current: current)
        if delta > 0, Date() > pasteUntilSafe {
            add(delta, source: "commit(cjk)")
        }
    }

    private func readFocusedText() -> String? {
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let el = focused else { return nil }
        let axEl = el as! AXUIElement

        // 排除自家进程
        var pid: pid_t = 0
        if AXUIElementGetPid(axEl, &pid) == .success, pid == ownPid { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &value) == .success,
              let str = value as? String else { return nil }
        lastAXChangeCheck(str)
        return str
    }

    // AX 值变化时间戳（供 idle 判定）
    private var lastSeenText: String?
    private func lastAXChangeCheck(_ t: String) {
        lock.lock()
        if t != lastSeenText { lastAXChangeAt = Date() }
        lastSeenText = t
        lock.unlock()
    }

    private func log(_ msg: String) {
        let line = "\(DateFormatter.logStamp.string(from: Date())) \(msg)\n"
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordBuddy/count_debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

extension DateFormatter {
    static let logStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
