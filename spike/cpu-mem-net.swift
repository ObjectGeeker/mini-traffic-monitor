import Foundation
import Darwin

// 1) CPU via host_processor_info
func cpuSample() -> (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)? {
    var count: mach_msg_type_number_t = 0
    var info: processor_info_array_t?
    var numCpus: natural_t = 0
    let kr = host_processor_info(host_t(mach_host_self()), PROCESSOR_CPU_LOAD_INFO,
                                 &numCpus, &info, &count)
    guard kr == KERN_SUCCESS, let info = info else { return nil }
    let ptr = UnsafeBufferPointer(start: info, count: Int(count))
    var u: UInt32 = 0, s: UInt32 = 0, i: UInt32 = 0, n: UInt32 = 0
    for c in 0..<Int(numCpus) {
        let base = Int(CPU_STATE_MAX) * c
        u += UInt32(bitPattern: ptr[base + Int(CPU_STATE_USER)])
        s += UInt32(bitPattern: ptr[base + Int(CPU_STATE_SYSTEM)])
        i += UInt32(bitPattern: ptr[base + Int(CPU_STATE_IDLE)])
        n += UInt32(bitPattern: ptr[base + Int(CPU_STATE_NICE)])
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
    return (u, s, i, n)
}

// 2) Memory via host_statistics64
func memSample() -> (appMB: Double, wiredMB: Double, compressedMB: Double, physMB: Double) {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(host_t(mach_host_self()), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return (0,0,0,0) }
    var phys: Int64 = 0
    var size = MemoryLayout<Int64>.stride
    sysctlbyname("hw.memsize", &phys, &size, nil, 0)
    let ps = Double(vm_kernel_page_size)
    let free = Double(stats.free_count) * ps
    let inactive = Double(stats.inactive_count) * ps
    let speculative = Double(stats.speculative_count) * ps
    let wired = Double(stats.wire_count) * ps
    let compressed = Double(stats.compressor_page_count) * ps
    let app = Double(stats.internal_page_count) * ps - compressed
    let total = Double(phys)
    // Activity Monitor "Memory Used" ≈ total - free - inactive - speculative (approximation)
    let used = total - free - inactive - speculative
    _ = (wired, compressed, app, used)
    return (app/1048576, wired/1048576, compressed/1048576, total/1048576)
}

// 3) Network via getifaddrs + sysctl NET_RT_IFLIST2 style (use if_data)
func netSample() -> [(name: String, inBytes: UInt64, outBytes: UInt64)] {
    var result: [(String, UInt64, UInt64)] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let head = ifap else { return [] }
    var p: UnsafeMutablePointer<ifaddrs>? = head
    while let cur = p {
        let fam = cur.pointee.ifa_addr.pointee.sa_family
        if fam == UInt8(AF_LINK) {
            let name = String(cString: cur.pointee.ifa_name)
            if let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self)
                let inb = UInt64(d.pointee.ifi_ibytes)
                let outb = UInt64(d.pointee.ifi_obytes)
                if inb > 0 || outb > 0 { result.append((name, inb, outb)) }
            }
        }
        p = cur.pointee.ifa_next
    }
    freeifaddrs(head)
    return result
}

// 4) Default route interface index
func defaultRouteIfIndex() -> Int? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
    var len = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
    return buf.withUnsafeBufferPointer { bp -> Int? in
        var off = 0
        while off + MemoryLayout<rt_msghdr>.stride <= len {
            let hdr = UnsafeRawPointer(bp.baseAddress!).advanced(by: off).assumingMemoryBound(to: rt_msghdr.self)
            let msgLen = Int(hdr.pointee.rtm_msglen)
            if msgLen <= 0 { break }
            if hdr.pointee.rtm_addrs & RTA_IFP != 0 {
                let saOff = off + MemoryLayout<rt_msghdr>.stride
                if saOff + MemoryLayout<sockaddr_dl>.stride <= len {
                    let sdl = UnsafeRawPointer(bp.baseAddress!).advanced(by: saOff).assumingMemoryBound(to: sockaddr_dl.self)
                    if sdl.pointee.sdl_family == UInt8(AF_LINK) { return Int(sdl.pointee.sdl_index) }
                }
            }
            off += msgLen
        }
        return nil
    }
}

print("=== CPU ticks ===")
if let a = cpuSample() { print("user=\(a.user) sys=\(a.sys) idle=\(a.idle) nice=\(a.nice)") } else { print("FAILED") }
print("=== MEMORY (MB) ===")
let m = memSample(); print("app=\(Int(m.appMB)) wired=\(Int(m.wiredMB)) compressed=\(Int(m.compressedMB)) physTotal=\(Int(m.physMB))")
print("=== NET IFACES ===")
for i in netSample() { print("\(i.name): in=\(i.inBytes) out=\(i.outBytes)") }
print("=== DEFAULT ROUTE IF INDEX ===")
print(String(describing: defaultRouteIfIndex()))
