import Foundation

final class TimedUndoManager: UndoManager {
    private let endGroupingInterval: TimeInterval = 1
    private var endGroupingTimer: Timer?
    private var coalescingDisabled = false
    /// Track when we're inside an undo/redo operation to pass through all group calls
    private(set) var isPerformingUndoRedo = false
    /// Track our own coalescing groups separately from NSUndoManager's internal groups
    private var hasOurCoalescingGroup = false

    override init() {
        super.init()
        groupsByEvent = false
    }

    /// Disables undo coalescing for the next operation.
    /// Call this before registering a standalone undo action (like find/replace).
    func disableUndoCoalescing() {
        // Close any existing coalescing group first
        if hasOurCoalescingGroup {
            cancelTimer()
            hasOurCoalescingGroup = false
            super.endUndoGrouping()
        }
        coalescingDisabled = true
    }

    /// Re-enables undo coalescing after a standalone operation.
    func enableUndoCoalescing() {
        coalescingDisabled = false
    }

    override func removeAllActions() {
        cancelTimer()
        hasOurCoalescingGroup = false
        super.removeAllActions()
    }

    override func beginUndoGrouping() {
        // During undo/redo, pass through to super so NSUndoManager's internal group management works
        if isPerformingUndoRedo {
            super.beginUndoGrouping()
            return
        }
        // For normal typing, coalesce by not creating nested groups
        if !hasOurCoalescingGroup {
            super.beginUndoGrouping()
            hasOurCoalescingGroup = true
            if endGroupingTimer == nil {
                scheduleTimer()
            }
        }
    }

    override func endUndoGrouping() {
        // During undo/redo, pass through to super so NSUndoManager's internal group management works
        if isPerformingUndoRedo {
            super.endUndoGrouping()
            return
        }
        cancelTimer()
        if hasOurCoalescingGroup {
            hasOurCoalescingGroup = false
            super.endUndoGrouping()
        }
    }

    override func undo() {
        // Close any open typing/coalescing group first
        if hasOurCoalescingGroup {
            cancelTimer()
            hasOurCoalescingGroup = false
            super.endUndoGrouping()
        }
        // Allow NSUndoManager to manage its own groups during undo
        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }
        super.undo()
    }

    override func redo() {
        // Close any open typing/coalescing group first
        if hasOurCoalescingGroup {
            cancelTimer()
            hasOurCoalescingGroup = false
            super.endUndoGrouping()
        }
        // Allow NSUndoManager to manage its own groups during redo
        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }
        super.redo()
    }
}

private extension TimedUndoManager {
    private func scheduleTimer() {
        let timer = Timer(timeInterval: endGroupingInterval, target: self, selector: #selector(timerDidTrigger), userInfo: nil, repeats: false)
        endGroupingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimer() {
        endGroupingTimer?.invalidate()
        endGroupingTimer = nil
    }

    @objc private func timerDidTrigger() {
        cancelTimer()
        endUndoGrouping()
    }
}
