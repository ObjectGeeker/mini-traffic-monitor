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

        // 1a「仅图标」预设：标记位非空（不会被当成「从未配置」而回退 .all），但不含 cpu/mem/net，
        // displayed() 原样放行，attributed() 里 cpu/mem/net 全不命中 → 落入空集渲染逻辑，直接是图标档
        check("iconOnlyMarker 非空（不会回退成 .all）", !Segment.iconOnlyMarker.isEmpty)
        check("displayed(iconOnlyMarker,0) 不含 cpu/mem/net",
              Sampler.displayed(enabled: .iconOnlyMarker, drops: 0).intersection(.all).isEmpty)
        check("displayed(iconOnlyMarker,9) 不含 cpu/mem/net(无需自动收缩也已是图标档)",
              Sampler.displayed(enabled: .iconOnlyMarker, drops: 9).intersection(.all).isEmpty)

        // 1b 无刘海兜底：safeMinX 不能退化到 0，否则挤压检测在无刘海屏幕上永不触发
        check("effectiveSafeMinX(nil)==110(无刘海兜底)", Sampler.effectiveSafeMinX(notchMinX: nil) == 110)
        check("effectiveSafeMinX(956)==956(刘海更靠右时刘海优先)", Sampler.effectiveSafeMinX(notchMinX: 956) == 956)
        check("effectiveSafeMinX(50)==110(刘海比兜底还靠左时兜底更保守)", Sampler.effectiveSafeMinX(notchMinX: 50) == 110)

        // 1c 收缩侧余量：净余量不足 20pt 仍判定不稳而继续收缩，不能刚过安全边界就停
        // 回归用例：真机实测 minX=968 safeMin=956（净余量仅 12pt），旧逻辑在此卡死（见 docs/requirements.md）
        check("shouldShrink(968,956)==true(净余量12pt<20pt,真机卡死复现)", Sampler.shouldShrink(minX: 968, safe: 956))
        check("shouldShrink(955,956)==true(已越界)", Sampler.shouldShrink(minX: 955, safe: 956))
        check("shouldShrink(976,956)==false(刚好够20pt余量)", !Sampler.shouldShrink(minX: 976, safe: 956))
        check("shouldShrink(996,956)==false(远超余量)", !Sampler.shouldShrink(minX: 996, safe: 956))

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
        // 无快照时信息区跳过：3 开关 + 2 内存内容 + 3 预设 + 开机自启 + 退出 + 4 分隔 = 14
        check("菜单项数 == 14（实际 \(titles.count)）", titles.count == 14)
        check("含 开机自启", titles.contains("开机自启"))
        check("含 栏内显示：CPU", titles.contains("栏内显示：CPU"))
        check("含 内存内容：压力", titles.contains("内存内容：压力"))
        check("含 预设：极简（仅网速）", titles.contains("预设：极简（仅网速）"))
        check("含 预设：仅图标（无数值）", titles.contains("预设：仅图标（无数值）"))
        check("含 退出项", titles.contains(where: { $0.hasPrefix("退出") }))

        print(ok ? "SELFTEST OK" : "SELFTEST FAILED")
        return ok
    }
}
