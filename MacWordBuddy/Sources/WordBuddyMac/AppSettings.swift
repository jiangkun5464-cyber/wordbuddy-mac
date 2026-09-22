import Foundation

// 与 Windows 版 AppSettings.cs 字段一一对应，配置文件可互相迁移
struct AppSettings: Codable {
    var Target: Int = 300
    var Mode: String = "up"                 // up = 累计模式, down = 倒数模式
    var AlwaysOnTop: Bool = true
    var Opacity: Double = 0.98
    var Left: Double? = nil
    var Top: Double? = nil
    var Theme: String = "dark"              // dark / light / pure
    var YuanPerThousand: Double = 50.0
    var CumulativeEnabled: Bool = true
    var CumulativeRounds: Int = 0
    var CumulativeChars: Int = 0

    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configURL, options: .atomic)
        }
    }
}
