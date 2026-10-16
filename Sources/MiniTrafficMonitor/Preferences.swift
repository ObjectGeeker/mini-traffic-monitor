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
            guard raw != 0 else { return .all }
            let s = Segment(rawValue: raw)
            return s.isEmpty ? .all : s
        }
        set { defaults.set(newValue.rawValue, forKey: "visibleSegments") }
    }

    var memoryMode: MemoryMode {
        get { MemoryMode(rawValue: defaults.integer(forKey: "memoryDisplayMode")) ?? .usage }
        set { defaults.set(newValue.rawValue, forKey: "memoryDisplayMode") }
    }
}
