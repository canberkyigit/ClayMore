import AppKit

// Test runner: `ClayMoreTests <suite>`. `./build.sh test` runs every suite in its own process
// with a fresh, empty CLAYMORE_DATA_DIR, since the store is a singleton loaded once per process.
setvbuf(stdout, nil, _IONBF, 0)
// Unbundled, the runner's preferences (current note, window frames) live under its process name.
UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
_ = NSApplication.shared

let suites: [String: (sampleData: Bool, run: () -> Void)] = [
    "save": (false, saveTests),
    "search": (true, searchTests),
    "ux": (true, uxTests),
    "click": (true, clickTests),
]
let name = CommandLine.arguments.dropFirst().first ?? ""
guard let suite = suites[name], let dir = ProcessInfo.processInfo.environment["CLAYMORE_DATA_DIR"] else {
    print("usage: CLAYMORE_DATA_DIR=<empty folder> ClayMoreTests \(suites.keys.sorted().joined(separator: "|"))")
    exit(2)
}
if suite.sampleData { SampleData.write(to: URL(fileURLWithPath: dir)) }
print("\(name):")
suite.run()
exit(failures == 0 ? 0 : 1)
