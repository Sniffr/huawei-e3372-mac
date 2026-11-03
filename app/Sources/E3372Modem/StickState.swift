import AppKit
import IOKit

/// What the USB bus says about the stick, independent of its web API.
enum StickUSB {
    case absent
    case cdMode      // 12d1:1f01, waiting for the driver to switch it
    case network     // switched; should answer on its web API

    static func current() -> StickUSB {
        // Matching on idVendor directly finds nothing outside driver
        // matching, so list every USB device and filter here.
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"),
                                           &iterator) == KERN_SUCCESS else { return .absent }
        defer { IOObjectRelease(iterator) }
        var state = StickUSB.absent
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            guard number(device, "idVendor") == 0x12d1 else { continue }
            if number(device, "idProduct") == 0x1f01 {
                if state == .absent { state = .cdMode }
            } else {
                state = .network
            }
        }
        return state
    }

    private static func number(_ device: io_object_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}

enum Driver {
    static let switchTool = "/usr/local/libexec/e3372-switch"
    static var installed: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.huawei-e3372.switch.plist")
    }
    static var canSwitch: Bool { FileManager.default.isExecutableFile(atPath: switchTool) }

    /// Runs the switch tool with the standard macOS admin password prompt.
    static func switchNow() async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var error: NSDictionary?
                let script = NSAppleScript(source: "do shell script \"\(switchTool)\" with administrator privileges")
                script?.executeAndReturnError(&error)
                cont.resume(returning: error == nil)
            }
        }
    }

    static let localNetworkSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
}
