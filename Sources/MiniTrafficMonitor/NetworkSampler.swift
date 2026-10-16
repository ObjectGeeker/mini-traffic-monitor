import Darwin
import Foundation
import SystemConfiguration

final class NetworkSampler {
    struct NetSample {
        /// nil = 首帧或接口切换帧（无有效差值）
        let downBytesPerSec: Double?
        let upBytesPerSec: Double?
        let interfaceName: String
        let ipAddress: String?
    }

    private var store: SCDynamicStore?
    private var prevBytes: (inb: UInt64, outb: UInt64)?
    private var prevTime: UInt64 = 0
    private var prevIface = ""
    private var onInterfaceChanged: (() -> Void)?
    private var cachedIface = ""
    private var cachedIP: String?

    init() {
        // 回调只能在 Create 时传入（SCDynamicStoreSetCallBack 未导入 Swift）；
        // store 声明为带默认值的 var，以便此处安全地取 self 指针填入 context
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "com.mini.trafficmonitor" as CFString, Self.storeCallback, &context)
    }

    /// 监听活动网卡变化（FR-4）：变化时立即重置基线并触发重渲染，不等下一个 1Hz tick
    func startMonitoring(_ onChange: @escaping () -> Void) {
        guard let store = store else { return }
        onInterfaceChanged = onChange
        SCDynamicStoreSetNotificationKeys(store, ["State:/Network/Global/IPv4"] as CFArray, [] as CFArray)
        SCDynamicStoreSetDispatchQueue(store, .main)
    }

    func sample() -> NetSample {
        let iface = activeInterface() ?? ""
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let cur = iface.isEmpty ? nil : Self.readBytes(iface)

        var down: Double?
        var up: Double?
        if let cur = cur, iface == prevIface, let pb = prevBytes, now > prevTime,
           cur.inb >= pb.inb, cur.outb >= pb.outb {
            let dt = Double(now - prevTime) / 1e9
            down = max(0, Double(cur.inb - pb.inb) / dt)
            up = max(0, Double(cur.outb - pb.outb) / dt)
        } else {
            down = nil
            up = nil
        }

        // 接口切换或计数器回退时重置基线，避免瞬间假峰值（FR-4）
        prevBytes = cur
        prevTime = now
        prevIface = iface
        if iface != cachedIface {
            cachedIface = iface
            cachedIP = iface.isEmpty ? nil : Self.readIPv4(iface)
        }
        return NetSample(downBytesPerSec: down, upBytesPerSec: up,
                         interfaceName: iface, ipAddress: cachedIP)
    }

    private static let storeCallback: SCDynamicStoreCallBack = { _, _, info in
        guard let info = info else { return }
        Unmanaged<NetworkSampler>.fromOpaque(info).takeUnretainedValue().handleInterfaceChanged()
    }

    private func handleInterfaceChanged() {
        prevBytes = nil
        prevIface = ""
        onInterfaceChanged?()
    }

    private func activeInterface() -> String? {
        guard let store = store else { return nil }
        guard let v = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }
        return v["PrimaryInterface"] as? String
    }

    private static func readIPv4(_ name: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return nil }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = head
        while let cur = p {
            if cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: cur.pointee.ifa_name) == name {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(cur.pointee.ifa_addr, UInt32(cur.pointee.ifa_addr.pointee.sa_len),
                               &buf, UInt32(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: buf)
                }
            }
            p = cur.pointee.ifa_next
        }
        return nil
    }

    private static func readBytes(_ name: String) -> (inb: UInt64, outb: UInt64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return nil }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = head
        while let cur = p {
            if cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: cur.pointee.ifa_name) == name,
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self)
                return (UInt64(d.pointee.ifi_ibytes), UInt64(d.pointee.ifi_obytes))
            }
            p = cur.pointee.ifa_next
        }
        return nil
    }
}
