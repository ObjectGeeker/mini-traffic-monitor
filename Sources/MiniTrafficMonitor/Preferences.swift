import Foundation

enum MemoryMode: Int {
    case usage = 0
    case pressure = 1
}

struct Segment: OptionSet {
    let rawValue: Int
    static let cpu = Segment(rawValue: 1 << 0)
    static let mem = Segment(rawValue: 1 << 1)
    static let net = Segment(rawValue: 1 << 2)
    static let all: Segment = [.cpu, .mem, .net]
    /// 「仅图标」预设的持久化标记位，不代表任何可显示指标。
    /// 单纯存 rawValue=0 会被 Preferences.enabledSegments 的 getter 当成「从未配置」而回退成 .all，
    /// 需要一个非零、且不含 cpu/mem/net 的值来表达「用户明确选了仅图标」
    static let iconOnlyMarker = Segment(rawValue: 1 << 3)
}

final class Preferences {
    static let shared = Preferences()
    // 打包态（bundle id == 域）用 .standard，其域即 com.mini.trafficmonitor；
    // 用同名 suite 会被 Foundation 拒绝（"does not make sense and will not work"）。
    // 松散二进制态（无 bundle id）才显式 suite，保证两种启动方式读同一份偏好。
    private var defaults: UserDefaults {
        if Bundle.main.bundleIdentifier == "com.mini.trafficmonitor" { return .standard }
        return UserDefaults(suiteName: "com.mini.trafficmonitor") ?? .standard
    }

    var enabledSegments: Segment {
        get {
            // 用 integer 而非 object as? Int：后者对 NSNumber 桥接可能失败而静默回退默认值
            let raw = defaults.integer(forKey: "visibleSegments")
            // 默认仅网速（而非三段全开）：平时栏内干净，压力大时交给 FR-1 收缩到图标档；
            // 想看 CPU/内存就手动勾选或切「完整」预设
            guard raw != 0 else { return .net }
            let s = Segment(rawValue: raw)
            return s.isEmpty ? .net : s
        }
        set { defaults.set(newValue.rawValue, forKey: "visibleSegments") }
    }

    var memoryMode: MemoryMode {
        get { MemoryMode(rawValue: defaults.integer(forKey: "memoryDisplayMode")) ?? .usage }
        set { defaults.set(newValue.rawValue, forKey: "memoryDisplayMode") }
    }
}
