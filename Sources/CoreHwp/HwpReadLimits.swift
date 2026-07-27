import Foundation

/// HWP stream을 읽을 때 허용할 최대 byte 수입니다.
public struct HwpReadLimits: HwpPrimitive {
    /// 기본 읽기 제한입니다.
    public static let `default` = HwpReadLimits(
        maxCompressedStreamBytes: 64 * 1024 * 1024,
        maxDecompressedStreamBytes: 256 * 1024 * 1024,
        maxAggregateStreamBytes: 1024 * 1024 * 1024
    )

    /// 압축된 OLE stream 입력에 허용할 최대 byte 수입니다.
    public let maxCompressedStreamBytes: Int

    /// 압축 해제 결과 또는 비압축 OLE stream에 허용할 최대 byte 수입니다.
    public let maxDecompressedStreamBytes: Int

    /// 한 파일이 읽어 보유하는 모든 stream byte 합계에 허용할 최대치입니다.
    /// 개별 stream 한도만으로는 유효한 자식 다수(BodyText·ViewText·BinData)로
    /// 집계 메모리 사용량이 무제한이 될 수 있습니다.
    public let maxAggregateStreamBytes: Int

    /// HWP stream 읽기 제한을 생성합니다.
    public init(
        maxCompressedStreamBytes: Int = 64 * 1024 * 1024,
        maxDecompressedStreamBytes: Int = 256 * 1024 * 1024,
        maxAggregateStreamBytes: Int = 1024 * 1024 * 1024
    ) {
        self.maxCompressedStreamBytes = maxCompressedStreamBytes
        self.maxDecompressedStreamBytes = maxDecompressedStreamBytes
        self.maxAggregateStreamBytes = maxAggregateStreamBytes
    }

    private enum CodingKeys: String, CodingKey {
        case maxCompressedStreamBytes, maxDecompressedStreamBytes, maxAggregateStreamBytes
    }

    /// main 아카이브에는 maxAggregateStreamBytes 키가 없다 — 기본 한도로 폴백해
    /// synthesized 디코더의 keyNotFound 실패를 막는다 (R61 #1).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxCompressedStreamBytes: try container.decodeIfPresent(
                Int.self, forKey: .maxCompressedStreamBytes
            ) ?? Self.default.maxCompressedStreamBytes,
            maxDecompressedStreamBytes: try container.decodeIfPresent(
                Int.self, forKey: .maxDecompressedStreamBytes
            ) ?? Self.default.maxDecompressedStreamBytes,
            maxAggregateStreamBytes: try container.decodeIfPresent(
                Int.self, forKey: .maxAggregateStreamBytes
            ) ?? Self.default.maxAggregateStreamBytes
        )
    }

    func validate() throws {
        try validatePositive(maxCompressedStreamBytes, name: "maxCompressedStreamBytes")
        try validatePositive(maxDecompressedStreamBytes, name: "maxDecompressedStreamBytes")
        try validatePositive(maxAggregateStreamBytes, name: "maxAggregateStreamBytes")
    }

    private func validatePositive(_ value: Int, name: String) throws {
        guard value > 0 else {
            throw HwpError.invalidDataLength(
                length: "HwpReadLimits.\(name) must be greater than 0, got \(value)"
            )
        }
    }
}
