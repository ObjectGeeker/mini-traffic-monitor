import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let agentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.mini.trafficmonitor.plist"

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentPath)
    }

    /// 首选 SMAppService；ad-hoc 签名下若失败则回退 LaunchAgent（FR-6）
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        if on {
            if smRegister() { return true }
            return installLaunchAgent()
        }
        smUnregister()
        removeLaunchAgent()
        return true
    }

    /// 最近一次 set 的实际生效途径，供菜单/诊断显示
    private(set) static var lastViaLaunchAgent = false

    private static func smRegister() -> Bool {
        do {
            try SMAppService.mainApp.register()
            lastViaLaunchAgent = false
            return true
        } catch {
            return false
        }
    }

    private static func smUnregister() {
        try? SMAppService.mainApp.unregister()
    }

    // MARK: - LaunchAgent 兜底

    private static func installLaunchAgent() -> Bool {
        guard let bin = Bundle.main.executableURL?.path else { return false }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>com.mini.trafficmonitor</string>
            <key>ProgramArguments</key><array><string>\(bin)</string></array>
            <key>RunAtLoad</key><true/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            let dir = (agentPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try plist.write(to: URL(fileURLWithPath: agentPath), atomically: true, encoding: .utf8)
            lastViaLaunchAgent = true
            return true
        } catch {
            return false
        }
    }

    private static func removeLaunchAgent() {
        try? FileManager.default.removeItem(atPath: agentPath)
    }

    /// 无头验证：注册 → 读状态 → 注销 → 确认恢复原状
    static func roundTripTest() -> (ok: Bool, detail: String) {
        let before = isEnabled
        let setOk = set(true)
        let enabled = isEnabled
        let sm = SMAppService.mainApp.status == .enabled
        let viaAgent = lastViaLaunchAgent
        set(false)
        let restored = isEnabled == before
        let ok = setOk && enabled && restored
        return (ok, "set=\(setOk) enabled=\(enabled) smEnabled=\(sm) viaAgent=\(viaAgent) restored=\(restored)")
    }
}
