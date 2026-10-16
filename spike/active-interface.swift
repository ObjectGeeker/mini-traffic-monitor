import Foundation
import SystemConfiguration

let store = SCDynamicStoreCreate(nil, "mtm-probe" as CFString, nil, nil)!
for family in ["IPv4", "IPv6"] {
    let key = "State:/Network/Global/\(family)" as CFString
    if let v = SCDynamicStoreCopyValue(store, key) as? [String: Any] {
        print("\(family): PrimaryInterface=\(v["PrimaryInterface"] ?? "nil") Router=\(v["Router"] ?? "nil")")
    } else {
        print("\(family): no value")
    }
}
// also try the direct service path
if let v = SCDynamicStoreCopyValue(store, "State:/Network/Interface/en0/IPv4" as CFString) as? [String: Any] {
    print("en0 IPv4: \(v["Addresses"] ?? "nil")")
}
