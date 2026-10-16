import Foundation
import Darwin
var s = vm_statistics64_data_t()
var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
let kr = withUnsafeMutablePointer(to: &s) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(host_t(mach_host_self()), HOST_VM_INFO64, $0, &c) }
}
guard kr == KERN_SUCCESS else { print("FAIL"); exit(1) }
var phys: Int64 = 0; var sz = MemoryLayout<Int64>.stride
sysctlbyname("hw.memsize", &phys, &sz, nil, 0)
let ps = Double(vm_kernel_page_size); let G = 1073741824.0
let total = Double(phys)
let free = Double(s.free_count) * ps
let active = Double(s.active_count) * ps
let inactive = Double(s.inactive_count) * ps
let spec = Double(s.speculative_count) * ps
let wired = Double(s.wire_count) * ps
let comp = Double(s.compressor_page_count) * ps
let internalP = Double(s.internal_page_count) * ps
let purgeable = Double(s.purgeable_count) * ps
let extFile = Double(s.external_page_count) * ps
let app = internalP - comp
let A = app + wired + comp
let B = total - free - spec - purgeable
let C = total - free
print(String(format: "physTotal   %6.2f G", total/G))
print(String(format: "  free      %6.2f G", free/G))
print(String(format: "  active    %6.2f G", active/G))
print(String(format: "  inactive  %6.2f G", inactive/G))
print(String(format: "  speculative %4.2f G", spec/G))
print(String(format: "  purgeable %6.2f G", purgeable/G))
print(String(format: "  wired     %6.2f G", wired/G))
print(String(format: "  compressed%6.2f G", comp/G))
print(String(format: "  internal  %6.2f G", internalP/G))
print(String(format: "  ext/file  %6.2f G", extFile/G))
print(String(format: "  app(int-c)%6.2f G", app/G))
print("---CANDIDATES---")
print(String(format: "A app+wired+comp        = %6.2f G  (%5.1f%%)", A/G, A/total*100))
print(String(format: "B total-free-spec-purge = %6.2f G  (%5.1f%%)", B/G, B/total*100))
print(String(format: "C total-free            = %6.2f G  (%5.1f%%)", C/G, C/total*100))
print(String(format: "D A + ext/file-backed   = %6.2f G  (%5.1f%%)", (A+extFile)/G, (A+extFile)/total*100))
