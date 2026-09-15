import Foundation

/**
 호환 문서

 Tag ID : HWPTAG_COMPATIBLE_DOCUMENT
 */
public struct HwpCompatibleDocument: HwpTagValidatedRecord, HwpRawPayloadRestoringRecord {
    static let expectedTag: HwpDocInfoTag = .compatibleDocument

    /** 대상 프로그램 */
    public let targetDocument: UInt32
    /** 대상 프로그램 필드의 원문 payload */
    @ExcludeEquatable
    public var targetDocumentRawPayload: Data
    public let layoutCompatibility: HwpLayoutCompatibility?
    @ExcludeEquatable
    public var trackChangeArray: [HwpTrackChange]
    @ExcludeEquatable
    public var rawPayload: Data
    @ExcludeEquatable
    public var unknownChildren: [HwpUnknownRecord]

    init() {
        targetDocument = 0
        targetDocumentRawPayload = Data()
        layoutCompatibility = HwpLayoutCompatibility()
        trackChangeArray = []
        rawPayload = Data()
        unknownChildren = []
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        targetDocument = try reader.read(UInt32.self)
        let targetPayload = try reader.consumedData(from: startOffset)
        targetDocumentRawPayload = targetPayload

        if let layoutCompatibility = children
            .first(where: { $0.tagId == HwpDocInfoTag.layoutCompatibility.rawValue })
        {
            self.layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibility)
        } else {
            layoutCompatibility = nil
        }
        trackChangeArray = try children
            .filter { $0.tagId == HwpDocInfoTag.trackChange.rawValue }
            .map(HwpTrackChange.load)
        rawPayload = targetPayload
        unknownChildren = Self.unconsumedRecords(from: children).map(HwpUnknownRecord.init)
    }

    /// HWPX 합성 전용 init — `hh:compatibleDocument@targetProgram`만 옮긴다 (#187).
    /// 레이아웃 호환성(표 56)은 OWPML의 35개 불리언 요소를 비트로 옮기는 표가 없어
    /// `layoutCompatibility`를 nil로 두고 그 요소를 `unknownChildren`으로 강등한다
    /// (`parseDiagnostics()`가 `docInfo.compatibleDocument` 경로로 보고한다).
    /// 원문 payload는 없다 — 바이너리 스트림이 아니므로 빈 `Data`다. 같은 파일에
    /// 두는 이유는 struct의 `let` 저장 속성을 다른 파일의 extension init이 직접
    /// 초기화할 수 없어서다.
    init(
        hwpxTarget target: HwpCompatibleDocumentTarget,
        unknownChildren: [HwpUnknownRecord]
    ) {
        targetDocument = target.rawValue
        targetDocumentRawPayload = Data()
        layoutCompatibility = nil
        trackChangeArray = []
        rawPayload = Data()
        self.unknownChildren = unknownChildren
    }
}

private extension HwpCompatibleDocument {
    static func unconsumedRecords(from children: [HwpRecord]) -> [HwpRecord] {
        var didConsumeLayoutCompatibility = false

        return children.filter { child in
            guard child.tagId == HwpDocInfoTag.layoutCompatibility.rawValue else {
                return child.tagId != HwpDocInfoTag.trackChange.rawValue
            }

            if didConsumeLayoutCompatibility {
                return true
            }
            didConsumeLayoutCompatibility = true
            return false
        }
    }
}
