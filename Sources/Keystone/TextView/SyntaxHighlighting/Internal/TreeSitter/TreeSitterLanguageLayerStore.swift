import Foundation

final class TreeSitterLanguageLayerStore {
    var allIDs: [UnsafeRawPointer] {
        lock.withLock {
            Array(store.keys)
        }
    }

    var allLayers: [TreeSitterLanguageLayer] {
        lock.withLock {
            Array(store.values)
        }
    }

    var isEmpty: Bool {
        lock.withLock {
            store.isEmpty
        }
    }

    private var store: [UnsafeRawPointer: TreeSitterLanguageLayer] = [:]
    // Use NSLock instead of DispatchSemaphore for priority inheritance support.
    // This prevents priority inversion when main thread waits for background thread.
    private let lock = NSLock()

    func storeLayer(_ layer: TreeSitterLanguageLayer, forKey key: UnsafeRawPointer) {
        lock.withLock {
            store[key] = layer
        }
    }

    func layer(forKey key: UnsafeRawPointer) -> TreeSitterLanguageLayer? {
        lock.withLock {
            store[key]
        }
    }

    func removeLayer(forKey key: UnsafeRawPointer) {
        lock.withLock {
            store.removeValue(forKey: key)
        }
    }

    func removeAll() {
        lock.withLock {
            store.removeAll()
        }
    }
}
