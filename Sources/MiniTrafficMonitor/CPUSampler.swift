import Darwin
import Foundation

struct CPUSample {
    let percent: Double
    let userPercent: Double
    let sysPercent: Double
}

final class CPUSampler {
    private struct Ticks {
        var user: UInt32 = 0
        var sys: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0
    }

    private var prev: Ticks?

    /// 聚合所有核心的占用率；首次采样无前值返回 nil
    func sample() -> CPUSample? {
        guard let cur = Self.readTicks() else { return nil }
        defer { prev = cur }
        guard let p = prev else { return nil }

        let du = cur.user &- p.user
        let ds = cur.sys &- p.sys
        let di = cur.idle &- p.idle
        let dn = cur.nice &- p.nice
        let busy = Double(du &+ ds &+ dn)
        let total = Double(du &+ ds &+ dn &+ di)
        guard total > 0 else { return CPUSample(percent: 0, userPercent: 0, sysPercent: 0) }
        return CPUSample(
            percent: min(100, busy / total * 100),
            userPercent: min(100, Double(du &+ dn) / total * 100),
            sysPercent: min(100, Double(ds) / total * 100)
        )
    }

    private static func readTicks() -> Ticks? {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var numCpus: natural_t = 0
        let kr = host_processor_info(host_t(mach_host_self()), PROCESSOR_CPU_LOAD_INFO, &numCpus, &info, &count)
        guard kr == KERN_SUCCESS, let info = info else { return nil }
        // 不释放则每秒泄漏一次（见需求文档附录 A.2）
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        let buf = UnsafeBufferPointer(start: info, count: Int(count))
        var t = Ticks()
        for c in 0..<Int(numCpus) {
            let base = c * Int(CPU_STATE_MAX)
            t.user &+= UInt32(bitPattern: buf[base + Int(CPU_STATE_USER)])
            t.sys &+= UInt32(bitPattern: buf[base + Int(CPU_STATE_SYSTEM)])
            t.idle &+= UInt32(bitPattern: buf[base + Int(CPU_STATE_IDLE)])
            t.nice &+= UInt32(bitPattern: buf[base + Int(CPU_STATE_NICE)])
        }
        return t
    }
}
