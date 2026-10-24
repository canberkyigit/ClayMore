#if DEBUG
import AppKit

/// Dev-only helpers (compiled out of release builds):
///   CLAYMORE_APPEARANCE=dark|light   force appearance
///   CLAYMORE_SNAPSHOT=/path/out.png  render the window content to PNG and quit
///   CLAYMORE_EXIT_AFTER_LAUNCH=1     quit right after the first frame (launch benchmark)
///   CLAYMORE_SIMULATE_LOGIN=1        behave as if launched as a login item (prints window visibility)
enum DebugHooks {
    private static let env = ProcessInfo.processInfo.environment

    static var simulateLoginLaunch: Bool { env["CLAYMORE_SIMULATE_LOGIN"] != nil }

    static func beforeLaunch() {
        switch env["CLAYMORE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    static func afterLaunch(window: NSWindow) {
        if simulateLoginLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                print("window visible: \(window.isVisible), app hidden: \(NSApp.isHidden)")
                exit(0)
            }
        }
        if env["CLAYMORE_EXIT_AFTER_LAUNCH"] != nil {
            DispatchQueue.main.async { exit(0) }
        }
        if let path = env["CLAYMORE_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let v = window.contentView!
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
}
#endif
