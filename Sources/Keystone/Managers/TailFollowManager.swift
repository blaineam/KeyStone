//
//  TailFollowManager.swift
//  Keystone
//
//  Monitors a file for changes and provides live updates (like `tail -f`).
//

import Foundation
import Combine

/// Manages tail-follow functionality for monitoring file changes in real-time.
///
/// Use this to watch log files or other files that are being actively written to.
///
/// Example usage:
/// ```swift
/// @StateObject private var tailFollow = TailFollowManager()
///
/// tailFollow.start(fileURL: logFileURL) { newContent in
///     self.textContent = newContent
/// }
/// ```
@MainActor
public class TailFollowManager: ObservableObject {
    /// Whether tail follow is currently active.
    @Published public var isEnabled: Bool = false

    /// The interval between file checks (in seconds).
    @Published public var updateInterval: TimeInterval = 1.0

    /// The URL of the file being monitored (if any).
    @Published public private(set) var monitoredFileURL: URL?

    private var timer: Timer?
    private var lastFileSize: UInt64 = 0
    private var lastModificationDate: Date?
    private var updateHandler: ((String) -> Void)?

    public init() {}

    deinit {
        timer?.invalidate()
    }

    /// Starts monitoring a file for changes.
    /// - Parameters:
    ///   - fileURL: The URL of the file to monitor.
    ///   - onUpdate: Callback invoked with the new file content when changes are detected.
    public func start(fileURL: URL, onUpdate: @escaping (String) -> Void) {
        stop()

        monitoredFileURL = fileURL
        updateHandler = onUpdate
        isEnabled = true

        // Get initial file state
        updateFileState(fileURL: fileURL)

        // Start the timer
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.checkForUpdates()
            }
        }
    }

    /// Stops monitoring the file.
    public func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        monitoredFileURL = nil
        updateHandler = nil
        lastFileSize = 0
        lastModificationDate = nil
    }

    /// Toggles tail follow on/off.
    /// - Parameters:
    ///   - fileURL: The URL of the file to monitor (used when enabling).
    ///   - onUpdate: Callback invoked with the new file content when changes are detected.
    public func toggle(fileURL: URL, onUpdate: @escaping (String) -> Void) {
        if isEnabled {
            stop()
        } else {
            start(fileURL: fileURL, onUpdate: onUpdate)
        }
    }

    private func updateFileState(fileURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { return }
        lastFileSize = attrs[.size] as? UInt64 ?? 0
        lastModificationDate = attrs[.modificationDate] as? Date
    }

    private func checkForUpdates() {
        guard let fileURL = monitoredFileURL,
              let updateHandler = updateHandler else { return }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { return }

        let currentSize = attrs[.size] as? UInt64 ?? 0
        let currentModDate = attrs[.modificationDate] as? Date

        // Check if file has changed
        let sizeChanged = currentSize != lastFileSize
        let dateChanged = currentModDate != lastModificationDate

        if sizeChanged || dateChanged {
            lastFileSize = currentSize
            lastModificationDate = currentModDate

            // Read the new content
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                updateHandler(content)
            } else if let content = try? String(contentsOf: fileURL, encoding: .ascii) {
                // Fallback to ASCII for binary-ish log files
                updateHandler(content)
            }
        }
    }
}

// MARK: - Tail Follow Options

public extension TailFollowManager {
    /// Common update intervals.
    enum UpdateFrequency: TimeInterval, CaseIterable, Identifiable {
        case fast = 0.5
        case normal = 1.0
        case slow = 2.0
        case verySlow = 5.0

        public var id: TimeInterval { rawValue }

        public var displayName: String {
            switch self {
            case .fast: return "Fast (0.5s)"
            case .normal: return "Normal (1s)"
            case .slow: return "Slow (2s)"
            case .verySlow: return "Very Slow (5s)"
            }
        }
    }

    /// Sets the update frequency using a preset.
    func setUpdateFrequency(_ frequency: UpdateFrequency) {
        updateInterval = frequency.rawValue
    }
}
