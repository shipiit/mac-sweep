import Foundation

extension AlertEngine {
    mutating func lowDisk(_ volume: VolumeStats, at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        guard volume.total > 0 else { return [] }
        let free = volume.available
        let fraction = Double(free) / Double(volume.total)
        let isLow = fraction < config.lowDiskFraction || free < config.lowDiskBytes
        let rearm = fraction >= config.lowDiskRearmFraction && free >= config.lowDiskRearmBytes
        let isCritical = free < config.lowDiskBytes / 3 || fraction < config.lowDiskFraction / 2
        let alert = track(.lowDisk, key: "disk", isActive: isLow, rearm: rearm, at: now, enabled: enabled) {
            SmartAlert(rule: .lowDisk, key: "disk", severity: isCritical ? .critical : .warning,
                       title: "Your disk is almost full",
                       message: "Only \(AlertText.bytes(free)) (\(AlertText.percent(fraction))) free. Run a scan to find space to reclaim.",
                       date: now)
        }
        return alert.map { [$0] } ?? []
    }

    mutating func memoryLeaks(_ processes: [ProcessLoad], at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        var keys: [String: () -> SmartAlert] = [:]
        for process in processes where process.memoryTrend.isSteadilyGrowing
            && process.memoryTrend.growth >= config.leakMinimumGrowth {
            let key = "leak:" + process.name
            let rate = AlertText.memory(Int64(process.memoryTrend.bytesPerMinute.rounded()))
            keys[key] = {
                SmartAlert(rule: .memoryLeak, key: key, severity: .warning,
                           title: "\(process.name) keeps using more memory",
                           message: "It grew \(AlertText.memory(process.memoryTrend.growth)) (about \(rate)/min). Restarting it usually frees the memory.",
                           date: now, subjectPath: process.path)
            }
        }
        return trackAll(.memoryLeak, prefix: "leak:", activeKeys: keys, at: now, enabled: enabled)
    }

    mutating func sustainedCPU(_ processes: [ProcessLoad], sampledAt: Date, at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        var streaks: [String: AlertEngineState.Streak] = [:]
        for process in processes where process.cpuPercent > config.cpuPercent {
            var streak = state.cpuStreaks[process.identity]
                ?? AlertEngineState.Streak(since: sampledAt, lastSeen: sampledAt, name: process.name)
            if sampledAt.timeIntervalSince(streak.lastSeen) > config.cpuMaxSampleGap {
                streak.since = sampledAt
            }
            streak.lastSeen = sampledAt
            streaks[process.identity] = streak
        }
        state.cpuStreaks = streaks

        var keys: [String: () -> SmartAlert] = [:]
        let threshold = Int(config.cpuPercent)
        for process in processes {
            guard let streak = streaks[process.identity],
                  sampledAt.timeIntervalSince(streak.since) >= config.cpuDuration else { continue }
            let key = "cpu:" + process.name
            let minutes = Int(sampledAt.timeIntervalSince(streak.since) / 60)
            keys[key] = {
                SmartAlert(rule: .sustainedCPU, key: key, severity: .warning,
                           title: "\(process.name) is using a lot of CPU",
                           message: "Above \(threshold)% for \(max(minutes, 2)) minutes (now \(Int(process.cpuPercent.rounded()))%). This drains battery and heats the Mac.",
                           date: now, subjectPath: process.path)
            }
        }
        return trackAll(.sustainedCPU, prefix: "cpu:", activeKeys: keys, at: now, enabled: enabled)
    }

    mutating func thermal(_ level: ThermalLevel, at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        let isHot = level == .serious || level == .critical
        let alert = track(.thermal, key: "thermal", isActive: isHot, rearm: !isHot, at: now, enabled: enabled) {
            SmartAlert(rule: .thermal, key: "thermal", severity: level == .critical ? .critical : .warning,
                       title: level == .critical ? "Your Mac is throttling" : "Your Mac is running hot",
                       message: "macOS is slowing the processor to cool down. Check Processes for heavy apps.",
                       date: now)
        }
        return alert.map { [$0] } ?? []
    }

    mutating func battery(_ health: Double, at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        guard let baseline = state.batteryBaseline else {
            state.batteryBaseline = health
            return []
        }
        if health > baseline {
            state.batteryBaseline = health
            return []
        }
        // Tolerance keeps an exact two-point drop from missing on floating-point rounding.
        guard enabled.contains(.batteryHealth), baseline - health >= config.batteryDrop - 1e-9 else { return [] }
        state.batteryBaseline = health
        let key = "battery:\(Int((health * 100).rounded()))"
        let alert = event(.batteryHealth, key: key, at: now) {
            SmartAlert(rule: .batteryHealth, key: key, severity: health < 0.8 ? .critical : .warning,
                       title: "Battery health dropped to \(AlertText.percent(health))",
                       message: "Down from \(AlertText.percent(baseline)) at the last reading."
                           + (health < 0.8 ? " Below 80% Apple considers the battery due for service." : ""),
                       date: now)
        }
        return alert.map { [$0] } ?? []
    }

    mutating func startup(_ items: [StartupFingerprint], at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        defer { state.startupBaseline = current }
        guard let baseline = state.startupBaseline, enabled.contains(.newStartupItem) else { return [] }
        return items.sorted { $0.id < $1.id }.compactMap { item in
            if let known = baseline[item.id] {
                guard known.executable != item.executable else { return nil }
                return event(.newStartupItem, key: "startup:changed:\(item.id):\(item.executable ?? "")", at: now) {
                    SmartAlert(rule: .newStartupItem, key: "startup:\(item.id)", severity: .critical,
                               title: "\(item.name) now runs a different program",
                               message: "This \(item.kind.label) changed to \(item.executable ?? "nothing"). If you didn't update the app, check it in Startup Items.",
                               date: now, subjectPath: item.kind == .loginItem ? item.executable : item.id)
                }
            }
            return event(.newStartupItem, key: "startup:new:\(item.id)", at: now) {
                SmartAlert(rule: .newStartupItem, key: "startup:\(item.id)", severity: .critical,
                           title: "New \(item.kind.label): \(item.name)",
                           message: "It will start automatically\(item.executable.map { " and runs \($0)" } ?? ""). If you didn't just install something, review it in Startup Items.",
                           date: now, subjectPath: item.kind == .loginItem ? item.executable : item.id)
            }
        }
    }

    mutating func trash(_ bytes: UInt64, at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        let isLarge = bytes > config.trashBytes
        let alert = track(.largeTrash, key: "trash", isActive: isLarge, rearm: !isLarge, at: now, enabled: enabled) {
            SmartAlert(rule: .largeTrash, key: "trash", severity: .info,
                       title: "\(AlertText.bytes(bytes)) is sitting in the Trash",
                       message: "Files in the Trash still take up disk space until you empty it.",
                       date: now)
        }
        return alert.map { [$0] } ?? []
    }
}
