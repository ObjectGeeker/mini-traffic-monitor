import AppKit

if ProcessInfo.processInfo.environment["MTM_SELFTEST"] != nil {
    exit(SelfTest.run() ? 0 : 1)
}

if ProcessInfo.processInfo.environment["MTM_LOGIN_TEST"] != nil {
    let r = LaunchAtLogin.roundTripTest()
    print("LOGINTEST \(r.detail)")
    exit(r.ok ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
