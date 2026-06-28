import Foundation

public struct HwpReadLimits: HwpPrimitive {
    public static let `default` = HwpReadLimits(
        maxCompressedStreamBytes: 64 * 1024 * 1024,
        maxDecompressedStreamBytes: 256 * 1024 * 1024
    )

    public let maxCompressedStreamBytes: Int
    public let maxDecompressedStreamBytes: Int

    public init(
        maxCompressedStreamBytes: Int = 64 * 1024 * 1024,
        maxDecompressedStreamBytes: Int = 256 * 1024 * 1024
    ) {
        self.maxCompressedStreamBytes = maxCompressedStreamBytes
        self.maxDecompressedStreamBytes = maxDecompressedStreamBytes
    }
}
