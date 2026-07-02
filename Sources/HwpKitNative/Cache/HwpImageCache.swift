import CoreGraphics
import Foundation

public actor HwpImageCache {
    private struct CachedEntry {
        let image: CGImage
        let bytes: Int
        var timestamp: Date
    }

    private let maxBytes: Int
    private var storage: [UInt32: CachedEntry] = [:]
    private var totalBytes: Int = 0

    /// In-flight decode tasks keyed by binaryDataIndex — coalesces concurrent fetches.
    private var inFlight: [UInt32: Task<CGImage?, Never>] = [:]

    public init(maxBytes: Int = 100_000_000) {
        self.maxBytes = maxBytes
    }

    public func fetch(_ key: UInt32, decode: @escaping @Sendable () async -> CGImage?) async -> CGImage? {
        if var entry = storage[key] {
            entry.timestamp = Date()
            storage[key] = entry
            return entry.image
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<CGImage?, Never> {
            await decode()
        }
        inFlight[key] = task
        let image = await task.value
        inFlight.removeValue(forKey: key)

        if let image {
            let bytes = image.width * image.height * 4
            storage[key] = CachedEntry(image: image, bytes: bytes, timestamp: Date())
            totalBytes += bytes
            await evict(target: maxBytes)
        }

        return image
    }

    public func evict(target: Int) async {
        guard totalBytes > target else { return }

        let sorted = storage.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            storage.removeValue(forKey: key)
            totalBytes -= entry.bytes
            if totalBytes <= target { break }
        }
    }

    public func clear() async {
        storage.removeAll()
        totalBytes = 0
    }

    public func count() async -> Int {
        storage.count
    }

    public func currentBytes() async -> Int {
        totalBytes
    }
}
