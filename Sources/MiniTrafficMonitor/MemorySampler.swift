import Darwin
import Foundation

final class MemorySampler {
    struct MemorySample {
        let usedBytes: Double
        let totalBytes: Double
        let wiredBytes: Double
        let compressedBytes: Double
        let percent: Double
        /// 1=normal 2=warning 4=critical（FR-8，M3 接入显示）
        let pressureLevel: Int
    }

    private static let totalBytes: Double = {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.stride
        sysctlbyname("hw.memsize", &v, &size, nil, 0)
        return Double(v)
    }()

    func sample() -> MemorySample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host_t(mach_host_self()), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let ps = Double(vm_kernel_page_size)
        let wired = Double(stats.wire_count) * ps
        let compressed = Double(stats.compressor_page_count) * ps
        // 口径 A（Q1 定案）：internal + wire，等价于活动监视器「已使用内存」
        let used = (Double(stats.internal_page_count) + Double(stats.wire_count)) * ps
        let total = Self.totalBytes

        return MemorySample(
            usedBytes: used,
            totalBytes: total,
            wiredBytes: wired,
            compressedBytes: compressed,
            percent: total > 0 ? min(100, used / total * 100) : 0,
            pressureLevel: Self.pressureLevel()
        )
    }

    private static func pressureLevel() -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &v, &size, nil, 0) == 0 else { return 1 }
        return Int(v)
    }
}
