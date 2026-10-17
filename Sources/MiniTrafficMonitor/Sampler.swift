import AppKit
import Foundation

final class Sampler {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let network = NetworkSampler()
    private weak var controller: StatusItemController?
    private var timer: Timer?
    private let debug = ProcessInfo.processInfo.environment["MTM_DEBUG"] != nil
    /// 在用户启用集合内被自动收缩丢弃的段数（刘海挤压）
    private var dropCount = 0
    private var calmTicks = 0
    private var tickCount = 0
    private(set) var displayedNow: Segment = []
    private var last: (c: CPUSample?, m: MemorySampler.MemorySample?, n: NetworkSampler.NetSample)?

    var autoShrunk: Bool { dropCount > 0 }

    init(controller: StatusItemController) {
        self.controller = controller
    }

    func start() {
        network.startMonitoring { [weak self] in
            self?.refresh()
        }
        tick()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 偏好或网卡变化后立即重渲染；降档纠偏交给下一个 tick 的稳定布局判断
    func refresh() {
        dropCount = 0
        render()
    }

    func snapshot() -> (c: CPUSample?, m: MemorySampler.MemorySample?, n: NetworkSampler.NetSample)? {
        last
    }

    private func tick() {
        last = (cpu.sample(), memory.sample(), network.sample())
        // 决策必须在 render 之前：window frame 异步更新，render 后立刻读到的永远是上一帧布局，
        // 会形成 1↔2 降档极限环（表现为每秒闪烁）。此处读到的是上一秒已稳定的布局。
        adjustFit()
        let text = render()
        tickCount += 1
        if tickCount % 5 == 1 {   // tooltip 无需每秒重设
            controller?.setToolTip(Self.tooltip(last))
        }
        if debug {
            var line = "[mtm] \(text) [drops=\(dropCount) en=\(Preferences.shared.enabledSegments.rawValue) mode=\(Preferences.shared.memoryMode.rawValue)]"
            if let m = last?.m {
                line += String(format: "  | used=%.1fG wired=%.2fG comp=%.2fG pressure=%d",
                               m.usedBytes / 1073741824, m.wiredBytes / 1073741824,
                               m.compressedBytes / 1073741824, m.pressureLevel)
            }
            if let minX = controller?.itemMinX {
                line += String(format: " minX=%.0f safeMin=%.0f", minX,
                               Self.effectiveSafeMinX(notchMinX: controller?.safeAreaMinX))
            }
            FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
        }
    }

    @discardableResult
    private func render() -> String {
        guard let l = last else { return "" }
        let shown = Self.displayed(enabled: Preferences.shared.enabledSegments, drops: dropCount)
        displayedNow = shown
        let attr = Self.attributed(cpu: l.c, mem: l.m, net: l.n,
                                   shown: shown, mode: Preferences.shared.memoryMode)
        controller?.update(attributed: attr)
        return attr.string
    }

    static func segmentNames(_ s: Segment) -> String {
        var names: [String] = []
        if s.contains(.cpu) { names.append("CPU") }
        if s.contains(.mem) { names.append("内存") }
        if s.contains(.net) { names.append("网速") }
        return names.isEmpty ? "无" : names.joined(separator: "+")
    }

    // MARK: - 显示集合：用户启用集合 − 自动收缩丢弃

    static func displayed(enabled: Segment, drops: Int) -> Segment {
        var result = enabled
        var n = drops
        for seg in [Segment.mem, .cpu, .net] {
            guard n > 0, result.contains(seg) else { continue }
            result = result.subtracting([seg])
            n -= 1
        }
        return result
    }

    private static func segmentCount(_ s: Segment) -> Int {
        [Segment.cpu, .mem, .net].reduce(0) { $0 + (s.contains($1) ? 1 : 0) }
    }

    /// 无刘海屏幕的左侧兜底余量：任何 App 菜单最窄也有 Apple 图标 + 应用名等，不可能挤到 0。
    /// 实测（人为填塞 6 个共 2520pt 的假状态项）：被挤压时左边缘稳定在几百 pt 的正值区间，
    /// 几乎不会归零/变负——纯靠 `minX < 0` 在无刘海屏幕上等于永远不收缩，此兜底把触发点提前。
    static let genericLeftMargin: CGFloat = 110

    /// 有刘海用刘海安全区左边界（更精确，是实测的物理遮挡边界）；无刘海时退到通用兜底余量
    static func effectiveSafeMinX(notchMinX: CGFloat?) -> CGFloat {
        max(notchMinX ?? 0, genericLeftMargin)
    }

    /// 收缩侧余量：净余量 < 20pt 时仍判定「不够稳」而继续降档，而不是刚越过安全边界就停。
    /// 20pt 复用文档已实测的状态项右边缘自身漂移量（见 docs/requirements.md「升档为何要慢」）——
    /// 小于这个量级的净余量本身就落在测量噪声带内，不能当作稳定 fit。
    /// 必须 < growMargin，否则两侧条件会在同一区间重叠，退化成每秒闪烁的降档/升档极限环。
    static let shrinkRestMargin: CGFloat = 20
    /// 升档侧余量（> shrinkRestMargin），与其之间留出 [safe+20, safe+40) 死区，
    /// 降档判定"当前档"、升档判定"预测的少一档"配置，两者互不重叠
    static let growMargin: CGFloat = 40

    /// 纯函数化的收缩判定，供 SelfTest 在无真实 NSStatusItem 时断言（同 effectiveSafeMinX 的做法）
    static func shouldShrink(minX: CGFloat, safe: CGFloat, margin: CGFloat = shrinkRestMargin) -> Bool {
        minX < safe + margin - 0.5
    }

    /// 净余量不足 shrinkRestMargin 即降档（立即）。
    /// 升档为**慢速自愈**：预测 fit 且余量 ≥ growMargin（大于实测 ~20pt 的右边缘漂移）并持续 30s 才升一档，
    /// 避免回到每秒极限环闪烁，同时能在菜单栏空间恢复后自动回升。
    private func adjustFit() {
        guard let minX = controller?.itemMinX, minX > 0 else { return }
        let safe = Self.effectiveSafeMinX(notchMinX: controller?.safeAreaMinX)
        let enabled = Preferences.shared.enabledSegments
        if Self.shouldShrink(minX: minX, safe: safe), dropCount < Self.segmentCount(enabled) {
            dropCount += 1
            calmTicks = 0
            render()
        } else if dropCount > 0 {
            calmTicks = predictedFits(drops: dropCount - 1, margin: Self.growMargin) ? calmTicks + 1 : 0
            if calmTicks >= 30 {
                calmTicks = 0
                dropCount -= 1
                render()
            }
        } else {
            calmTicks = 0
        }
    }

    private func predictedFits(drops: Int, margin: CGFloat) -> Bool {
        guard let ctrl = controller, let maxX = ctrl.itemMaxX else { return false }
        let shown = Self.displayed(enabled: Preferences.shared.enabledSegments, drops: drops)
        let dummy = Self.attributed(
            cpu: CPUSample(percent: 88, userPercent: 8, sysPercent: 8),
            mem: MemorySampler.MemorySample(usedBytes: 1, totalBytes: 2, wiredBytes: 0,
                                            compressedBytes: 0, percent: 88, pressureLevel: 1),
            net: NetworkSampler.NetSample(downBytesPerSec: 8888, upBytesPerSec: 8888, interfaceName: "", ipAddress: nil),
            shown: shown, mode: Preferences.shared.memoryMode)
        return (maxX - ctrl.width(of: dummy.string)) >= Self.effectiveSafeMinX(notchMinX: ctrl.safeAreaMinX) + margin
    }

    // MARK: - 定宽格式化（FR-1）：字段宽度恒定，避免状态项宽度每秒变化导致相邻图标抖动

    /// 字体查找有成本，1Hz 下每秒调用，缓存为静态常量
    static let menuFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func attributed(cpu: CPUSample?, mem: MemorySampler.MemorySample?, net: NetworkSampler.NetSample,
                           shown: Segment, mode: MemoryMode) -> NSAttributedString {
        let font = menuFont
        let base: [NSAttributedString.Key: Any] = [.font: font]
        var parts: [NSAttributedString] = []

        if shown.contains(.cpu) {
            parts.append(NSAttributedString(string: "C" + pctField(cpu?.percent) + "%", attributes: base))
        }
        if shown.contains(.mem) {
            if mode == .pressure {
                let (glyph, color) = pressureGlyph(mem?.pressureLevel)
                let s = NSMutableAttributedString(string: "M" + glyph, attributes: base)
                s.addAttribute(.foregroundColor, value: color,
                               range: NSRange(location: 1, length: (glyph as NSString).length))
                parts.append(s)
            } else {
                parts.append(NSAttributedString(string: "M" + pctField(mem?.percent) + "%", attributes: base))
            }
        }
        if shown.contains(.net) {
            parts.append(NSAttributedString(string: "↓" + rateField(net.downBytesPerSec), attributes: base))
            parts.append(NSAttributedString(string: "↑" + rateField(net.upBytesPerSec), attributes: base))
        }
        if parts.isEmpty {
            // 最终档：菜单栏连仅网速档都放不下时，只留一个压力状态点（~10pt），
            // 保证任何拥挤程度下都可见、可点击打开全量面板
            let (glyph, color) = pressureGlyph(mem?.pressureLevel)
            let s = NSMutableAttributedString(string: glyph, attributes: base)
            s.addAttribute(.foregroundColor, value: color,
                           range: NSRange(location: 0, length: (glyph as NSString).length))
            parts.append(s)
        }

        let out = NSMutableAttributedString()
        for (i, p) in parts.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: " ", attributes: base)) }
            out.append(p)
        }
        return out
    }

    static func pressureGlyph(_ level: Int?) -> (String, NSColor) {
        switch level {
        case 2: return ("▲", .systemYellow)
        case 4: return ("■", .systemRed)
        default: return ("●", .systemGreen)
        }
    }

    static func pctField(_ v: Double?) -> String {
        guard let v = v else { return pad3("--") }
        return String(format: "%3d", Int(v.rounded()))
    }

    static func rateField(_ bytesPerSec: Double?) -> String {
        guard let bps = bytesPerSec else { return String(format: "%4d", 0) + "B" }
        let (v, unit) = scale(bps)
        // 99.95 是 %4.1f 会进位成 5 字符("100.0")的临界点
        let num = v < 99.95 ? String(format: "%4.1f", v) : String(format: "%4d", Int(v.rounded()))
        return num + unit
    }

    static func scale(_ bytesPerSec: Double) -> (value: Double, unit: String) {
        if bytesPerSec < 1024 { return (bytesPerSec, "B") }
        if bytesPerSec < 1048576 { return (bytesPerSec / 1024, "K") }
        if bytesPerSec < 1073741824 { return (bytesPerSec / 1048576, "M") }
        return (bytesPerSec / 1073741824, "G")
    }

    private static func pad3(_ s: String) -> String {
        String(repeating: " ", count: max(0, 3 - s.count)) + s
    }

    // MARK: - 悬停全量视图（FR-1 tooltip）

    static func tooltip(_ l: (c: CPUSample?, m: MemorySampler.MemorySample?, n: NetworkSampler.NetSample)?) -> String {
        guard let l = l else { return "MiniTrafficMonitor" }
        var lines: [String] = []
        if let c = l.c {
            lines.append(String(format: "CPU   %.1f%%  (user %.1f / sys %.1f)", c.percent, c.userPercent, c.sysPercent))
        }
        if let m = l.m {
            lines.append(String(format: "内存  %.1f / %.0f GB  (%.1f%%)",
                                m.usedBytes / 1073741824, m.totalBytes / 1073741824, m.percent))
            lines.append(String(format: "      wired %.1f G · compressed %.1f G · 压力 %@",
                                m.wiredBytes / 1073741824, m.compressedBytes / 1073741824,
                                pressureWord(m.pressureLevel)))
        }
        let n = l.n
        let iface = n.interfaceName.isEmpty ? "无活动网卡" : n.interfaceName
        lines.append("网络  \(iface)\(n.ipAddress.map { " (\($0))" } ?? "")")
        lines.append(String(format: "      ↓ %@   ↑ %@", fullRate(n.downBytesPerSec), fullRate(n.upBytesPerSec)))
        return lines.joined(separator: "\n")
    }

    static func pressureWord(_ level: Int) -> String {
        switch level {
        case 2: return "警告(黄)"
        case 4: return "严重(红)"
        default: return "正常(绿)"
        }
    }

    static func fullRate(_ bytesPerSec: Double?) -> String {
        guard let bps = bytesPerSec else { return "0 B/s" }
        let (v, u) = scale(bps)
        let unitName: String
        switch u {
        case "K": unitName = "KB/s"
        case "M": unitName = "MB/s"
        case "G": unitName = "GB/s"
        default: unitName = "B/s"
        }
        return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, unitName)
    }
}
