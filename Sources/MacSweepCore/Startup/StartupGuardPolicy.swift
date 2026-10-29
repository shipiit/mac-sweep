import Foundation

/// A launch item the guard stopped (or wants to stop) until you decide about it.
public struct HeldStartupItem: Identifiable, Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        /// Booted out and disabled automatically (your own agents need no password).
        case blocked
        /// All-user agent or daemon: waiting for you to press Block (needs your password).
        case awaitingBlock
    }

    public let fingerprint: StartupFingerprint
    public let detected: Date
    public var status: Status

    public var id: String { fingerprint.id }
    public var plistPath: String { fingerprint.id }

    public init(fingerprint: StartupFingerprint, detected: Date, status: Status) {
        self.fingerprint = fingerprint
        self.detected = detected
        self.status = status
    }
}

public struct StartupGuardEvent: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let date: Date
    public let name: String
    public let path: String
    public let action: String

    public init(id: UUID = UUID(), date: Date, name: String, path: String, action: String) {
        self.id = id
        self.date = date
        self.name = name
        self.path = path
        self.action = action
    }
}

/// What to do after comparing the launch folders with the approved baseline.
public struct StartupGuardDecision: Sendable, Equatable {
    /// Your own agents: bootout + disable right away, no password needed.
    public var autoBlock: [LaunchItem] = []
    /// All-user agents and daemons: notify and offer Block.
    public var askToBlock: [LaunchItem] = []
    /// Held entries whose plist is gone; drop them from the list.
    public var vanished: [String] = []

    public var isEmpty: Bool { autoBlock.isEmpty && askToBlock.isEmpty && vanished.isEmpty }
}

public enum StartupGuardPolicy {
    /// Launch agents and daemons only; login items are handled by macOS's own prompt.
    public static func baseline(from items: [LaunchItem]) -> [String: StartupFingerprint] {
        Dictionary(items.map { ($0.plistPath, StartupFingerprint($0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// New plists, or known plists that now run a different program, that aren't already held.
    public static func decide(baseline: [String: StartupFingerprint], held: [HeldStartupItem], current: [LaunchItem]) -> StartupGuardDecision {
        let heldIDs = Set(held.map(\.id))
        var decision = StartupGuardDecision()
        for item in current where !heldIDs.contains(item.plistPath) {
            if let known = baseline[item.plistPath], known.executable == item.executable { continue }
            if item.scope == .userAgent {
                decision.autoBlock.append(item)
            } else {
                decision.askToBlock.append(item)
            }
        }
        let currentIDs = Set(current.map(\.plistPath))
        decision.vanished = held.map(\.id).filter { !currentIDs.contains($0) }
        return decision
    }

    /// Records the decision in the archive: new items become held, vanished ones are dropped.
    public static func apply(_ decision: StartupGuardDecision, to archive: inout StartupGuardArchive, blockedIDs: Set<String>, at now: Date) {
        let vanished = Set(decision.vanished)
        for entry in archive.held where vanished.contains(entry.id) {
            archive.log(StartupGuardEvent(date: now, name: entry.fingerprint.name, path: entry.id, action: "Removed from disk"))
        }
        archive.held.removeAll { vanished.contains($0.id) }
        for item in decision.autoBlock {
            let blocked = blockedIDs.contains(item.plistPath)
            archive.held.append(HeldStartupItem(fingerprint: StartupFingerprint(item), detected: now,
                                                status: blocked ? .blocked : .awaitingBlock))
            archive.log(StartupGuardEvent(date: now, name: item.label, path: item.plistPath,
                                          action: blocked ? "Blocked automatically" : "Couldn't block automatically"))
        }
        for item in decision.askToBlock {
            archive.held.append(HeldStartupItem(fingerprint: StartupFingerprint(item), detected: now, status: .awaitingBlock))
            archive.log(StartupGuardEvent(date: now, name: item.label, path: item.plistPath, action: "Detected, waiting for you"))
        }
    }
}
