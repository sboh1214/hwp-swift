import Foundation

/// HWP stream을 읽을 때 허용할 최대 byte 수입니다.
public struct HwpReadLimits: HwpPrimitive {
    /// 기본 읽기 제한입니다.
    public static let `default` = HwpReadLimits(
        maxCompressedStreamBytes: 64 * 1024 * 1024,
        maxDecompressedStreamBytes: 256 * 1024 * 1024
    )

    /// 압축된 OLE stream 입력에 허용할 최대 byte 수입니다.
    public let maxCompressedStreamBytes: Int

    /// 압축 해제 결과 또는 비압축 OLE stream에 허용할 최대 byte 수입니다.
    public let maxDecompressedStreamBytes: Int

    /// HWP stream 읽기 제한을 생성합니다.
    public init(
        maxCompressedStreamBytes: Int = 64 * 1024 * 1024,
        maxDecompressedStreamBytes: Int = 256 * 1024 * 1024
    ) {
        self.maxCompressedStreamBytes = maxCompressedStreamBytes
        self.maxDecompressedStreamBytes = maxDecompressedStreamBytes
    }

    func validate() throws {
        try validatePositive(maxCompressedStreamBytes, name: "maxCompressedStreamBytes")
        try validatePositive(maxDecompressedStreamBytes, name: "maxDecompressedStreamBytes")
    }

    private func validatePositive(_ value: Int, name: String) throws {
        guard value > 0 else {
            throw HwpError.invalidDataLength(
                length: "HwpReadLimits.\(name) must be greater than 0, got \(value)"
            )
        }
    }
}
