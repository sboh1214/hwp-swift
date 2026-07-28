import Foundation

/// HWP stream을 읽을 때 허용할 상한입니다 (byte 수와 레코드 트리 깊이).
///
/// 두 종류는 **error 분류가 다릅니다**. byte 한도 3종은 stream read 단계의
/// 자원 한도라 `streamSizeLimitExceeded`·`aggregateStreamSizeLimitExceeded`로
/// 보고되고, optional stream(ViewText)의 폴백을 뚫고 전파됩니다.
/// `maxNestingDepth`는 이미 읽어 들인 byte를 파싱하는 단계의 **구조 유효성**
/// 한도라 인접한 level jump 가드와 같은 `invalidRecordTree`로 보고되고,
/// optional stream의 파싱 폴백에 동일하게 흡수됩니다 — 깊게 중첩된 ViewText는
/// 정의상 손상·적대 입력이므로 BodyText 렌더로 폴백하는 것이 맞습니다.
public struct HwpReadLimits: HwpPrimitive {
    /// 기본 읽기 제한입니다.
    public static let `default` = HwpReadLimits(
        maxCompressedStreamBytes: 64 * 1024 * 1024,
        maxDecompressedStreamBytes: 256 * 1024 * 1024,
        maxAggregateStreamBytes: 1024 * 1024 * 1024,
        maxNestingDepth: 64
    )

    /// 압축된 OLE stream 입력에 허용할 최대 byte 수입니다.
    public let maxCompressedStreamBytes: Int

    /// 압축 해제 결과 또는 비압축 OLE stream에 허용할 최대 byte 수입니다.
    public let maxDecompressedStreamBytes: Int

    /// 한 파일이 읽어 보유하는 모든 stream byte 합계에 허용할 최대치입니다.
    /// 개별 stream 한도만으로는 유효한 자식 다수(BodyText·ViewText·BinData)로
    /// 집계 메모리 사용량이 무제한이 될 수 있습니다.
    public let maxAggregateStreamBytes: Int

    /// 레코드 트리에 허용할 최대 중첩 깊이입니다.
    /// 레코드 헤더의 level은 10비트(≤1023)라 스펙만으로는 수백 단계 중첩이
    /// 가능한데, typed 디코더들이 그 트리를 재귀로 내려가므로(표 셀 문단·
    /// 리스트 컨트롤·글상자·메모) 조작 문서가 catch 불가능한 스택 오버플로를
    /// 일으킬 수 있습니다. 실문서 실측 최대 level은 5입니다.
    public let maxNestingDepth: Int

    /// HWP stream 읽기 제한을 생성합니다.
    public init(
        maxCompressedStreamBytes: Int = 64 * 1024 * 1024,
        maxDecompressedStreamBytes: Int = 256 * 1024 * 1024,
        maxAggregateStreamBytes: Int = 1024 * 1024 * 1024,
        maxNestingDepth: Int = 64
    ) {
        self.maxCompressedStreamBytes = maxCompressedStreamBytes
        self.maxDecompressedStreamBytes = maxDecompressedStreamBytes
        self.maxAggregateStreamBytes = maxAggregateStreamBytes
        self.maxNestingDepth = maxNestingDepth
    }

    private enum CodingKeys: String, CodingKey {
        case maxCompressedStreamBytes, maxDecompressedStreamBytes, maxAggregateStreamBytes
        case maxNestingDepth
    }

    /// 구 아카이브에는 maxAggregateStreamBytes·maxNestingDepth 키가 없다 —
    /// 기본 한도로 폴백해 synthesized 디코더의 keyNotFound 실패를 막는다 (R61 #1).
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
            ) ?? Self.default.maxAggregateStreamBytes,
            maxNestingDepth: try container.decodeIfPresent(
                Int.self, forKey: .maxNestingDepth
            ) ?? Self.default.maxNestingDepth
        )
    }

    func validate() throws {
        try validatePositive(maxCompressedStreamBytes, name: "maxCompressedStreamBytes")
        try validatePositive(maxDecompressedStreamBytes, name: "maxDecompressedStreamBytes")
        try validatePositive(maxAggregateStreamBytes, name: "maxAggregateStreamBytes")
        try validatePositive(maxNestingDepth, name: "maxNestingDepth")
    }

    private func validatePositive(_ value: Int, name: String) throws {
        guard value > 0 else {
            throw HwpError.invalidDataLength(
                length: "HwpReadLimits.\(name) must be greater than 0, got \(value)"
            )
        }
    }
}
