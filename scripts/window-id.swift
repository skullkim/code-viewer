import CoreGraphics
import Foundation

// Finds an on-screen window number by its owning application, without the accessibility
// permissions AppleScript needs. Used by the screenshot helper for design-fidelity checks.
let ownerName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "CodeNavigator"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

for window in windows {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == ownerName,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let height = bounds["Height"] as? Double, height > 100
    else {
        continue
    }
    print(number)
    exit(0)
}
exit(1)
