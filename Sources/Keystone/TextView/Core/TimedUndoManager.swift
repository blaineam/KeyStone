import Foundation
import QuartzCore

final class TimedUndoManager: UndoManager {
    private let endGroupingInterval: TimeInterval = 1
    private var endGroupingTimer: Timer?
    private var coalescingDisabled = false
    /// Track when we're inside an undo/redo operation to pass through all group calls
    private(set) var isPerformingUndoRedo = false
    /// Track our own coalescing groups separately from NSUndoManager's internal groups
    private var hasOurCoalescingGroup = false
    /// Prevent reentrant undo/redo calls from rapid button clicks
    private var isProcessingUndoRedo = false
    /// Queue pending undo/redo operations
    private var pendingUndoRedoCount = 0
    private var pendingIsUndo = true

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
        // If already processing, queue up the operation and return immediately
        if isProcessingUndoRedo {
            if pendingIsUndo {
                pendingUndoRedoCount += 1
            } else {
                // Switching direction cancels pending ops in opposite direction
                pendingUndoRedoCount = max(0, pendingUndoRedoCount - 1)
                if pendingUndoRedoCount == 0 {
                    pendingIsUndo = true
                }
            }
            return
        }

        performUndoRedo(isUndo: true)
    }

    override func redo() {
        // If already processing, queue up the operation and return immediately
        if isProcessingUndoRedo {
            if !pendingIsUndo {
                pendingUndoRedoCount += 1
            } else {
                // Switching direction cancels pending ops in opposite direction
                pendingUndoRedoCount = max(0, pendingUndoRedoCount - 1)
                if pendingUndoRedoCount == 0 {
                    pendingIsUndo = false
                }
            }
            return
        }

        performUndoRedo(isUndo: false)
    }

    private func performUndoRedo(isUndo: Bool) {
        isProcessingUndoRedo = true
        pendingIsUndo = isUndo
        pendingUndoRedoCount = 0

        // Close any open typing/coalescing group first
        if hasOurCoalescingGroup {
            cancelTimer()
            hasOurCoalescingGroup = false
            super.endUndoGrouping()
        }

        // Batch display updates to prevent visual artifacts
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Allow NSUndoManager to manage its own groups during undo/redo
        isPerformingUndoRedo = true
        if isUndo {
            super.undo()
        } else {
            super.redo()
        }
        isPerformingUndoRedo = false

        CATransaction.commit()

        isProcessingUndoRedo = false

        // Process any queued operations on next run loop to allow UI to update
        if pendingUndoRedoCount > 0 {
            let queuedCount = pendingUndoRedoCount
            let queuedIsUndo = pendingIsUndo
            pendingUndoRedoCount = 0

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for _ in 0..<queuedCount {
                    if queuedIsUndo {
                        if self.canUndo {
                            self.undo()
                        }
                    } else {
                        if self.canRedo {
                            self.redo()
                        }
                    }
                }
            }
        }
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
