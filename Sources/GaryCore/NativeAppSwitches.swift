import Foundation
import CoreFoundation

public enum NativeSwitchError: LocalizedError {
    case unsupportedFormat, ambiguousApp
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "macOS's app visibility list has an unsupported format. No icons were changed."
        case .ambiguousApp: return "macOS has duplicate app visibility records. No icons were changed."
        }
    }
}

/// Decodes the Swift-encoded dictionary without rebuilding or dropping unknown fields.
/// Only a verified third-party application's isAllowed Boolean is ever changed.
public struct NativeAppSwitches {
    private struct Row {
        var index: Int
        var key: String
        var owners: Set<String>
        var allowed: Bool
    }
    public var entries: [Any]
    private var rows: [Row] = []

    public init(entries: [Any]) throws {
        guard entries.count.isMultiple(of: 2) else { throw NativeSwitchError.unsupportedFormat }
        self.entries = entries
        var seen = Set<String>()
        for index in stride(from: 0, to: entries.count, by: 2) {
            guard let key = entries[index] as? [String: Any],
                  let bundle = key["bundle"] as? [String: Any],
                  let id = bundle["_0"] as? String,
                  let value = entries[index + 1] as? [String: Any],
                  let bool = value["isAllowed"] as? NSNumber,
                  CFGetTypeID(bool) == CFBooleanGetTypeID() else { continue }
            guard seen.insert(id).inserted else { throw NativeSwitchError.ambiguousApp }
            let locations = value["menuItemLocations"] as? [[String: Any]] ?? []
            var owners: Set<String> = [id]
            for location in locations {
                if let bundle = location["bundle"] as? [String: Any], let owner = bundle["_0"] as? String {
                    owners.insert(owner)
                }
            }
            rows.append(Row(index: index + 1, key: id, owners: owners, allowed: bool.boolValue))
        }
        if !entries.isEmpty, rows.isEmpty { throw NativeSwitchError.unsupportedFormat }
    }

    /// Records contain original values only for switches Gary Tools changed.
    /// Existing user-disabled apps stay disabled, even while revealing.
    public mutating func apply(allowing allowed: Set<String>?, ownID: String,
                               originals: inout [String: Bool]) {
        for row in rows {
            var current = row.allowed
            if let original = originals.removeValue(forKey: row.key) {
                if !current { current = original }
            }
            let protected = row.owners.contains(ownID) || row.owners.contains { $0.hasPrefix("com.apple.") }
            let shouldHide = allowed.map { row.owners.isDisjoint(with: $0) } ?? false
            if !protected, shouldHide, current {
                originals[row.key] = current
                current = false
            }
            if current != row.allowed, var value = entries[row.index] as? [String: Any] {
                value["isAllowed"] = current
                entries[row.index] = value
            }
        }
    }

    public var allowedStates: [String: Bool] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.allowed) })
    }
}
