import AppKit
import Foundation

/// 无 UI 自测：MTM_SELFTEST=1 运行，验证 M3 核心逻辑（显示集合 / 定宽 / 压力符号）
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) {
            print((cond ? "PASS  " : "FAIL  ") + name)
            if !cond { ok = false }
        }

        // 1 显示集合：降档顺序 mem -> cpu -> net，且永不为空
        check("displayed(all,0)==all", Sampler.displayed(enabled: .all, drops: 0) == .all)
        check("displayed(all,1)==cpu+net", Sampler.displayed(enabled: .all, drops: 1) == [.cpu, .net])
        check("displayed(all,2)==net", Sampler.displayed(enabled: .all, drops: 2) == [.net])
        check("displayed(all,3)==空(状态点档)", Sampler.displayed(enabled: .all, drops: 3) == [])
        check("displayed(all,9)==空(封顶)", Sampler.displayed(enabled: .all, drops: 9) == [])
        check("displayed(cpu+mem,1)==cpu", Sampler.displayed(enabled: [.cpu, .mem], drops: 1) == [.cpu])
        check("displayed(cpu+mem,2)==空", Sampler.displayed(enabled: [.cpu, .mem], drops: 2) == [])
        check("displayed(net,1)==空", Sampler.displayed(enabled: [.net], drops: 1) == [])

        // 2 定宽：任意数值帧在 usage / pressure 两模式下各自宽度恒定
        let cpuVals: [Double?] = [nil, 0, 5, 9, 10, 99, 100]
        let rateVals: [Double?] = [nil, 0, 9.94, 9.96, 10, 99.94, 99.96, 100, 1023, 1048576, 1073741824]
        var usageWidths = Set<Double>()
        var pressureWidths = Set<Double>()
        for c in cpuVals {
            for m in cpuVals {
                for d in rateVals {
                    for u in rateVals {
                        let net = NetworkSampler.NetSample(downBytesPerSec: d, upBytesPerSec: u,
                                                           interfaceName: "en0", ipAddress: nil)
                        let mem = MemorySampler.MemorySample(usedBytes: 1, totalBytes: 2, wiredBytes: 0,
                                                             compressedBytes: 0, percent: m ?? 0, pressureLevel: 1)
                        let cpu = c.map { CPUSample(percent: $0, userPercent: 0, sysPercent: 0) }
                        let r = { (v: Double) in (v * 100).rounded() / 100 }
                        usageWidths.insert(r(Sampler.attributed(cpu: cpu, mem: mem, net: net, shown: .all, mode: .usage).size().width))
                        pressureWidths.insert(r(Sampler.attributed(cpu: cpu, mem: mem, net: net, shown: .all, mode: .pressure).size().width))
                    }
                }
            }
        }
        check("usage 模式宽度恒定（\(usageWidths.count) 种）", usageWidths.count == 1)
        check("pressure 模式宽度恒定（\(pressureWidths.count) 种）", pressureWidths.count == 1)

        // 3 压力符号映射（FR-8）
        check("pressure 1 -> ●", Sampler.pressureGlyph(1).0 == "●")
        check("pressure 2 -> ▲", Sampler.pressureGlyph(2).0 == "▲")
        check("pressure 4 -> ■", Sampler.pressureGlyph(4).0 == "■")
        check("pressure nil -> ●", Sampler.pressureGlyph(nil).0 == "●")

        // 4 字段定宽
        check("pctField 恒 3 字符", Set([nil, 0.0, 9.0, 10.0, 99.0, 100.0].map { Sampler.pctField($0).count }) == [3])
        check("rateField 恒 5 字符", Set([nil, 0.0, 9.94, 99.96, 1023.0, 1048576.0].map { Sampler.rateField($0).count }) == [5])

        // 5 下拉面板结构（FR-5）：菜单点击无法无头验证，但构造路径可以
        let controller = StatusItemController()
        let sampler = Sampler(controller: controller)
        let builder = MenuBuilder(sampler: sampler)
        let menu = NSMenu()
        builder.menuNeedsUpdate(menu)
        let titles = menu.items.map { $0.title }
        // 无快照时信息区跳过：3 开关 + 2 内存内容 + 2 预设 + 开机自启 + 退出 + 4 分隔 = 13
        check("菜单项数 == 13（实际 \(titles.count)）", titles.count == 13)
        check("含 开机自启", titles.contains("开机自启"))
        check("含 栏内显示：CPU", titles.contains("栏内显示：CPU"))
        check("含 内存内容：压力", titles.contains("内存内容：压力"))
        check("含 预设：极简（仅网速）", titles.contains("预设：极简（仅网速）"))
        check("含 退出项", titles.contains(where: { $0.hasPrefix("退出") }))

        print(ok ? "SELFTEST OK" : "SELFTEST FAILED")
        return ok
    }
}
