import Foundation

/// Clipboard restoration and a later synthetic paste are one serial operation.
@MainActor public final class DeliveryQueue {
    public typealias Job = (@escaping () -> Void) -> Void
    private var pending: [Job] = []
    private var current: UUID?
    public init() {}
    public func enqueue(_ job: @escaping Job) { pending.append(job); startNext() }
    private func startNext() {
        guard current == nil, !pending.isEmpty else { return }
        let id = UUID(), job = pending.removeFirst(); current = id
        job { [weak self] in
            guard let self, self.current == id else { return }
            self.current = nil; self.startNext()
        }
    }
}
