import AppKit

final class MenuBuilder: NSObject, NSMenuDelegate {
    private weak var sampler: Sampler?

    init(sampler: Sampler) {
        self.sampler = sampler
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = Preferences.shared

        addInfoItems(to: menu)
        if let s = sampler, s.autoShrunk {
            let note = s.displayedNow.isEmpty
                ? "        ⚠ 菜单栏空间不足，已精简为状态点（点击看全量）"
                : "        ⚠ 菜单栏空间不足，已自动精简为：\(Sampler.segmentNames(s.displayedNow))"
            menu.addItem(info(note))
        }
        menu.addItem(.separator())

        for (title, seg) in [("栏内显示：CPU", Segment.cpu),
                             ("栏内显示：内存", Segment.mem),
                             ("栏内显示：网速", Segment.net)] {
            let it = NSMenuItem(title: title, action: #selector(toggleSegment(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = seg
            it.state = prefs.enabledSegments.contains(seg) ? .on : .off
            menu.addItem(it)
        }

        for (title, mode) in [("内存内容：占用率", MemoryMode.usage),
                              ("内存内容：压力", MemoryMode.pressure)] {
            let it = NSMenuItem(title: title, action: #selector(setMemoryMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = mode
            it.state = prefs.memoryMode == mode ? .on : .off
            menu.addItem(it)
        }

        menu.addItem(.separator())
        for (title, preset) in [("预设：完整（三段全开）", Segment.all),
                                ("预设：极简（仅网速）", Segment.net),
                                ("预设：仅图标（无数值）", Segment.iconOnlyMarker)] {
            let it = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = preset
            menu.addItem(it)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MiniTrafficMonitor", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 信息区（FR-5：始终展示全部四指标，是栏内显示的全量兜底视图）

    private func addInfoItems(to menu: NSMenu) {
        guard let snap = sampler?.snapshot() else { return }

        if let c = snap.c {
            menu.addItem(info(String(format: "CPU     %.1f%%  (user %.1f / sys %.1f)",
                                       c.percent, c.userPercent, c.sysPercent)))
        } else {
            menu.addItem(info("CPU     --"))
        }

        if let m = snap.m {
            menu.addItem(info(String(format: "内存    %.1f / %.0f GB  (%.1f%%)",
                                      m.usedBytes / 1073741824, m.totalBytes / 1073741824, m.percent)))
            menu.addItem(info(String(format: "        wired %.1f G · compressed %.1f G · 压力 %@",
                                      m.wiredBytes / 1073741824, m.compressedBytes / 1073741824,
                                      Sampler.pressureWord(m.pressureLevel))))
        }

        let n = snap.n
        let iface = n.interfaceName.isEmpty ? "无活动网卡" : n.interfaceName
        menu.addItem(info("网络    \(iface)\(n.ipAddress.map { " (\($0))" } ?? "")"))
        menu.addItem(info(String(format: "        ↓ %@   ↑ %@",
                                  Sampler.fullRate(n.downBytesPerSec), Sampler.fullRate(n.upBytesPerSec))))
    }

    private func info(_ title: String) -> NSMenuItem {
        // 无 action/target：不可点击但正常着色，作为只读信息行
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    // MARK: - 动作

    @objc private func toggleSegment(_ sender: NSMenuItem) {
        guard let seg = sender.representedObject as? Segment else { return }
        var enabled = Preferences.shared.enabledSegments
        if enabled.contains(seg) {
            let after = enabled.subtracting([seg])
            guard !after.isEmpty else { return }   // 至少保留一段
            enabled = after
        } else {
            enabled.insert(seg)
        }
        Preferences.shared.enabledSegments = enabled
        sampler?.refresh()
    }

    @objc private func setMemoryMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? MemoryMode else { return }
        Preferences.shared.memoryMode = mode
        sampler?.refresh()
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Segment else { return }
        Preferences.shared.enabledSegments = preset
        sampler?.refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
