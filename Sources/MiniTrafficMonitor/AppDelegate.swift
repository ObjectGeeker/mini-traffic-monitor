import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var sampler: Sampler?
    // NSMenu.delegate 为 unsafe_unretained，必须强持有 MenuBuilder
    private var menuBuilder: MenuBuilder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController()
        statusItem = controller

        let s = Sampler(controller: controller)
        sampler = s

        let builder = MenuBuilder(sampler: s)
        menuBuilder = builder
        let menu = NSMenu()
        menu.delegate = builder
        controller.setMenu(menu)

        s.start()

        let msg = "[mtm] launched policy=\(NSApp.activationPolicy().rawValue)(1=accessory) "
            + "statusBarThickness=\(NSStatusBar.system.thickness)\n"
        FileHandle.standardError.write(msg.data(using: .utf8)!)

        if ProcessInfo.processInfo.environment["MTM_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                let suiteVal = UserDefaults(suiteName: "com.mini.trafficmonitor")?.object(forKey: "visibleSegments") ?? "nil"
                let line = String(format: "[mtm] itemMinX=%.0f safeMin=%.0f suiteDirect=%@ prefsEn=%d\n",
                                  self?.statusItem?.itemMinX ?? -1,
                                  self?.statusItem?.safeAreaMinX ?? 0,
                                  String(describing: suiteVal),
                                  Preferences.shared.enabledSegments.rawValue)
                FileHandle.standardError.write(line.data(using: .utf8)!)
            }
        }
    }
}
