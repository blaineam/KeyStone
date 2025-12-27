//
//  DisplayLinkController.swift
//  Keystone
//
//  Provides smooth, frame-synchronized updates using CADisplayLink.
//  Inspired by Runestone framework's approach to smooth scrolling and updates.
//

import Foundation
import QuartzCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A controller that manages display-link synchronized updates
/// for smooth animations and scroll-synchronized rendering.
public class DisplayLinkController {

    /// Callback type for display link updates
    public typealias UpdateCallback = (CFTimeInterval) -> Void

    /// The update callback called on each frame
    public var onUpdate: UpdateCallback?

    /// Whether the display link is currently running
    public private(set) var isRunning = false

    /// The timestamp of the last update
    public private(set) var lastUpdateTime: CFTimeInterval = 0

    /// The current frame rate
    public var frameRate: Double {
        #if os(iOS)
        return Double(displayLink?.preferredFramesPerSecond ?? 60)
        #else
        // macOS CVDisplayLink doesn't expose frame rate directly, assume 60
        return 60.0
        #endif
    }

    #if os(iOS)
    private var displayLink: CADisplayLink?
    #elseif os(macOS)
    private var displayLink: CVDisplayLink?
    private var displayLinkCallback: CVDisplayLinkOutputCallback?
    #endif

    // MARK: - Initialization

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Control

    /// Starts the display link
    public func start() {
        guard !isRunning else { return }

        #if os(iOS)
        displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
        #elseif os(macOS)
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let displayLink = displayLink {
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
                guard let userInfo = userInfo else { return kCVReturnSuccess }
                let controller = Unmanaged<DisplayLinkController>.fromOpaque(userInfo).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.handleMacDisplayLink()
                }
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(displayLink)
        }
        #endif

        isRunning = true
        lastUpdateTime = CACurrentMediaTime()
    }

    /// Stops the display link
    public func stop() {
        guard isRunning else { return }

        #if os(iOS)
        displayLink?.invalidate()
        displayLink = nil
        #elseif os(macOS)
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        #endif

        isRunning = false
    }

    /// Temporarily pauses the display link
    public func pause() {
        #if os(iOS)
        displayLink?.isPaused = true
        #elseif os(macOS)
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        #endif
    }

    /// Resumes a paused display link
    public func resume() {
        #if os(iOS)
        displayLink?.isPaused = false
        #elseif os(macOS)
        if let displayLink = displayLink {
            CVDisplayLinkStart(displayLink)
        }
        #endif
        lastUpdateTime = CACurrentMediaTime()
    }

    // MARK: - Private

    #if os(iOS)
    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        let currentTime = displayLink.timestamp
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        onUpdate?(deltaTime)
    }
    #elseif os(macOS)
    private func handleMacDisplayLink() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        onUpdate?(deltaTime)
    }
    #endif
}

// MARK: - Throttled Update Controller

/// A controller that throttles updates to avoid excessive work
public class ThrottledUpdateController {

    /// Minimum time between updates in seconds
    public var minimumInterval: CFTimeInterval = 1.0 / 60.0 // 60 fps

    /// Last update timestamp
    private var lastUpdateTime: CFTimeInterval = 0

    /// Pending work item
    private var pendingWorkItem: DispatchWorkItem?

    /// Whether an update is scheduled
    public private(set) var isUpdatePending = false

    // MARK: - Scheduling

    /// Schedules an update if enough time has passed since the last one
    /// - Parameter work: The work to perform
    public func scheduleUpdate(_ work: @escaping () -> Void) {
        let currentTime = CACurrentMediaTime()
        let timeSinceLastUpdate = currentTime - lastUpdateTime

        if timeSinceLastUpdate >= minimumInterval {
            // Enough time has passed, execute immediately
            lastUpdateTime = currentTime
            work()
        } else if !isUpdatePending {
            // Schedule for later
            isUpdatePending = true
            let delay = minimumInterval - timeSinceLastUpdate

            pendingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastUpdateTime = CACurrentMediaTime()
                self.isUpdatePending = false
                work()
            }
            pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        // If update is already pending, the pending work will handle it
    }

    /// Cancels any pending update
    public func cancelPendingUpdate() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        isUpdatePending = false
    }

    /// Forces an immediate update, canceling any pending one
    public func forceUpdate(_ work: @escaping () -> Void) {
        cancelPendingUpdate()
        lastUpdateTime = CACurrentMediaTime()
        work()
    }
}

// MARK: - Scroll Synchronizer

/// Synchronizes updates with scroll position for smooth rendering
public class ScrollSynchronizer {

    /// The display link controller
    private let displayLink = DisplayLinkController()

    /// The throttled update controller for non-critical updates
    private let throttledUpdater = ThrottledUpdateController()

    /// Current scroll velocity (points per second)
    public private(set) var scrollVelocity: CGFloat = 0

    /// Previous scroll offset for velocity calculation
    private var previousScrollOffset: CGFloat = 0

    /// Whether scrolling is currently happening
    public private(set) var isScrolling = false

    /// Callback for scroll-synchronized updates
    public var onScrollUpdate: ((CGFloat, CGFloat) -> Void)? // offset, velocity

    /// Callback for idle updates (when scrolling stops)
    public var onIdleUpdate: (() -> Void)?

    // MARK: - Initialization

    public init() {
        displayLink.onUpdate = { [weak self] deltaTime in
            self?.handleFrame(deltaTime: deltaTime)
        }
    }

    // MARK: - Scroll Tracking

    /// Call this when scroll offset changes
    public func updateScrollOffset(_ offset: CGFloat) {
        let delta = offset - previousScrollOffset
        scrollVelocity = delta / CGFloat(max(0.001, CACurrentMediaTime() - displayLink.lastUpdateTime))
        previousScrollOffset = offset

        if !isScrolling {
            isScrolling = true
            displayLink.start()
        }
    }

    /// Call this when scrolling ends
    public func scrollingDidEnd() {
        isScrolling = false
        scrollVelocity = 0

        // Keep display link running briefly for smooth deceleration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, !self.isScrolling else { return }
            self.displayLink.stop()
            self.onIdleUpdate?()
        }
    }

    // MARK: - Private

    private func handleFrame(deltaTime: CFTimeInterval) {
        if isScrolling {
            onScrollUpdate?(previousScrollOffset, scrollVelocity)
        }
    }
}
