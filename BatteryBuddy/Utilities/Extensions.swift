import Foundation
import Darwin

func pathForPID(_ pid: pid_t) -> String? {
    let maxSize = 4 * Int(MAXPATHLEN)
    var buffer = [CChar](repeating: 0, count: maxSize)
    let result = proc_pidpath(pid, &buffer, UInt32(maxSize))
    guard result > 0 else { return nil }
    return String(cString: buffer)
}

func appBundlePath(from executablePath: String) -> String? {
    let components = executablePath.components(separatedBy: "/")
    for (index, component) in components.enumerated() where component.hasSuffix(".app") {
        return components[0...index].joined(separator: "/")
    }
    return nil
}

extension Double {
    var formattedWatts: String {
        if self >= 1.0 {
            return String(format: "%.1fW", self)
        }
        return String(format: "%.0fmW", self * 1000)
    }
}

extension Int {
    var formattedDuration: String {
        let hours = self / 60
        let mins = self % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
