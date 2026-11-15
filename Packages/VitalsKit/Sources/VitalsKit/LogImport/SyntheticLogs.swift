import Foundation

/// Synthetic system files for the Simulator, timed to a given hot spell so cause-finding can be seen.
/// They are written in the same layouts as the test fixtures and named "...-synthetic" so they are
/// obvious in the Logs list. Never shown unless the person asks for them in the debug menu.
public enum SyntheticLogs {
    public static func files(around spell: HotSpell) -> [(name: String, text: String)] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        let n = DateFormatter()
        n.locale = Locale(identifier: "en_US_POSIX")
        n.dateFormat = "yyyy-MM-dd-HHmmss"
        func t(_ offset: TimeInterval) -> Date { spell.start.addingTimeInterval(offset) }
        func header(_ d: Date, _ bug: String, _ name: String) -> String {
            #"{"timestamp":"\#(f.string(from: d))","bug_type":"\#(bug)","name":"\#(name)","os_version":"iPhone OS 27.1 (synthetic)"}"#
        }
        let cpu1 = t(8 * 60), cpu2 = t(25 * 60), jet = t(15 * 60), crash = t(30 * 60), wake = t(-10 * 60)
        func cpuBody(_ who: String, _ d: Date, _ secs: Int) -> String {
            "Date/Time:        \(f.string(from: d))\nCommand:          \(who)\nEvent:            cpu usage\nCPU:              \(secs) seconds cpu time over 180 seconds (\(secs * 100 / 180)% cpu average), exceeding limit of 50% cpu over 180 seconds\n"
        }
        let jetBody = #"{"date":"\#(f.string(from: jet))","largestProcess":"mediaanalysisd","memoryStatus":{"pageSize":16384},"processes":[{"name":"Safari","rpages":21000,"reason":"vm-pageshortage"},{"name":"mediaanalysisd","rpages":118000}]}"#
        let crashBody = #"{"procName":"Instagram","captureTime":"\#(f.string(from: crash))","exception":{"type":"EXC_RESOURCE","signal":"SIGKILL"}}"#
        let wakeBody = "Date/Time:        \(f.string(from: wake))\nCommand:          locationd\nWakeups:          45001 wakeups over the last 270 seconds\n"
        return [
            ("mediaanalysisd.cpu_resource-\(n.string(from: cpu1))-synthetic.ips", header(cpu1, "202", "mediaanalysisd") + "\n" + cpuBody("mediaanalysisd", cpu1, 160)),
            ("Instagram.cpu_resource-\(n.string(from: cpu2))-synthetic.ips", header(cpu2, "202", "Instagram") + "\n" + cpuBody("Instagram", cpu2, 95)),
            ("JetsamEvent-\(n.string(from: jet))-synthetic.ips", header(jet, "298", "JetsamEvent") + "\n" + jetBody),
            ("Instagram-\(n.string(from: crash))-synthetic.ips", header(crash, "309", "Instagram") + "\n" + crashBody),
            ("locationd.wakeups_resource-\(n.string(from: wake))-synthetic.ips", header(wake, "142", "locationd") + "\n" + wakeBody),
            ("Analytics-\(n.string(from: spell.start))-synthetic.ips.ca.synced",
             header(spell.start, "211", "analytics") + "\n" + #"{"message":{"last_value_MaximumCapacityPercent":86,"last_value_CycleCount":431},"name":"BatteryHealthDaily"}"# + "\n"),
        ]
    }
}
