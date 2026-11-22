import Foundation

public struct AppIdentity: Equatable {
    public let owner: String
    public let bundleIDs: Set<String>
    public init(owner: String, bundleIDs: Set<String>) {
        self.owner = owner
        self.bundleIDs = bundleIDs.union([owner])
    }
}

/// Everything is tucked away unless pinned. System apps and our own controls survive.
public struct VisibilityPolicy: Codable, Equatable {
    public var pinnedBundleIDs: Set<String>
    public init(pinnedBundleIDs: Set<String> = []) { self.pinnedBundleIDs = pinnedBundleIDs }

    public func isPinned(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.") || pinnedBundleIDs.contains(bundleID)
    }

    public func allowlist(apps: [AppIdentity], ownBundleID: String) -> Set<String> {
        var allowed = pinnedBundleIDs.union([ownBundleID])
        for app in apps where app.owner == ownBundleID || isPinned(app.owner) {
            allowed.formUnion(app.bundleIDs)
        }
        for app in apps where !app.bundleIDs.isDisjoint(with: pinnedBundleIDs) {
            allowed.formUnion(app.bundleIDs)
        }
        return allowed
    }

    public mutating func setPinned(_ bundleID: String, _ pinned: Bool) {
        if pinned { pinnedBundleIDs.insert(bundleID) }
        else { pinnedBundleIDs.remove(bundleID) }
    }
}

public struct HoverRevealGate {
    private var enteredAt: TimeInterval?
    private var fired = false
    private var wasCollapsed = false
    private var waitingForExit = false
    public init() {}

    public mutating func update(inside: Bool, collapsed: Bool, enabled: Bool, now: TimeInterval) -> Bool {
        if collapsed && !wasCollapsed && inside {
            // User just clicked the menu bar arrow to collapse; require pointer to leave first.
            waitingForExit = true
        }
        wasCollapsed = collapsed

        guard collapsed, enabled else {
            enteredAt = nil
            fired = false
            waitingForExit = false
            return false
        }
        if !inside {
            enteredAt = nil
            fired = false
            waitingForExit = false
            return false
        }
        if waitingForExit {
            return false
        }
        if enteredAt == nil { enteredAt = now }
        guard !fired, now - enteredAt! >= 0.35 else { return false }
        fired = true
        return true
    }
}

/// Rejects callbacks from an activation superseded by a newer request or reveal.
public struct ActivationRevision {
    public private(set) var value = 0
    public init() {}
    @discardableResult public mutating func next() -> Int { value += 1; return value }
    public func isCurrent(_ revision: Int) -> Bool { revision == value }
}
