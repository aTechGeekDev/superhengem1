import Foundation

/// Engine settings, without a rebuild. Defaults below, then the Performance settings,
/// then Documents/henge-env.txt (KEY=VALUE per line, # comments; {Documents} in a value is that folder) overrides them all.
/// Applied at launch and again before each Mac starts, so changes need no relaunch.
enum EngineTuning {
    static let refreshKey = "henge.perf.hz"
    static let superblocksKey = "henge.perf.superblocks"
    static let wfiSpinKey = "henge.perf.wfiSpin"
    static let fastFlushKey = "henge.perf.fastFlush"
    static let statsKey = "henge.perf.engineStats"
    static let sharpScalingKey = "henge.display.sharpScaling"
    static let highPriorityKey = "henge.perf.highPriority"
    static let gpuOrderingKey = "henge.display.gpuOrdering"

    static let defaults: [String: String] = [
        // 60, not 120: every frame macOS draws is emulated and replayed, so 120 Hz
        // halves the CPU left for apps for animation few will notice.
        "HV_HZ": "60",         // the refresh rate macOS is told its display has
        "HV_WFI_SPIN": "0",    // microseconds an idle CPU watches for work before sleeping
        "HV_FLUSH": "2",       // disk flush: F_BARRIERFSYNC, ordered but without a full fsync
        // Engine statistics off: with them on every CPU counts into shared counters, each dispatcher cache miss
        // walks the page tables again to say what missed, and every 10 s CPU 0 walks the whole block hash (a hitch).
        "HV_STATS": "0",       // seconds between engine stats lines in the log; 0 = off
    ]

    static func apply() {
        var env = defaults
        let d = UserDefaults.standard
        if [30, 120].contains(d.integer(forKey: refreshKey)) { env["HV_HZ"] = String(d.integer(forKey: refreshKey)) }
        if d.bool(forKey: superblocksKey) { env["HV_SUPERBLOCKS"] = "1" } else { unsetenv("HV_SUPERBLOCKS") }
        // On unless turned off: an app opening is thousands of messages between macOS's processes, each a CPU
        // waking another, and waking a sleeping host thread takes far longer than the 50 µs watched for first.
        if d.object(forKey: wfiSpinKey) as? Bool ?? true { env["HV_WFI_SPIN"] = "50" }
        if d.object(forKey: fastFlushKey) as? Bool == false { env["HV_FLUSH"] = "0" }
        if d.bool(forKey: statsKey) { env["HV_STATS"] = "10" }
        // The Mac's CPUs at the GPU replay's priority (user-interactive), so iOS keeps them on the performance cores.
        if d.bool(forKey: highPriorityKey) { env["HV_QOS"] = "ui" } else { unsetenv("HV_QOS") }
        // Display changes of 0.2.1, each switchable to tell which one a drawing problem comes from.
        if d.object(forKey: sharpScalingKey) as? Bool == false { env["HV_PVG_SCALE"] = "native" } else { unsetenv("HV_PVG_SCALE") }
        if d.object(forKey: gpuOrderingKey) as? Bool == false { env["HV_PVG_ORDER"] = "0" } else { unsetenv("HV_PVG_ORDER") }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // GPU command trace: on while Documents/trace-on exists (it is checked every frame, so it can be toggled live).
        env["HV_PVG_TRACE_FILE"] = docs.appendingPathComponent("trace-on").path
        let url = docs.appendingPathComponent("henge-env.txt")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
                // {Documents} stands for this folder: its absolute path changes when Henge is reinstalled.
                env[String(line[..<eq]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "{Documents}", with: docs.path)
            }
        }
        for (k, v) in env.sorted(by: { $0.key < $1.key }) {
            setenv(k, v, 1)
            HengeLog.log("tuning", "\(k)=\(v)")
        }
    }
}
