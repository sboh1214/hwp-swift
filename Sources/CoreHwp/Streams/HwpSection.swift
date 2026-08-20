import Foundation

/**
 본문
 */
public struct HwpSection: HwpFromDataWithVersion {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public var paragraph: [HwpParagraph]
    public var unknownRecords: [HwpUnknownRecord]
    /// `HwpLoadOptions.recoverPartialContent` 복구 모드에서 이 구역이 파싱
    /// 실패를 placeholder(빈 문서 템플릿 문단)로 대체한 것이면 그 원인 설명.
    /// 정상 파싱은 nil. 진단 표면이므로 Equatable/Hashable에 참여한다.
    public var parseFailure: String?

    init() {
        rawPayload = Data()
        paragraph = [HwpParagraph.blankDocumentParagraph()]
        unknownRecords = []
        parseFailure = nil
    }

    /// 복구 모드에서 파싱에 실패한 구역을 대신하는 placeholder — 빈 문서
    /// 템플릿 문단(sectionDef + column 컨트롤 포함)을 채워 조판 전제를
    /// 지키고, 구역 수를 보존해 뒤 구역의 자리가 밀리지 않게 한다 (#65).
    /// `rawPayload`에는 실패한 구역 스트림 원본을 실어(보존 모드 한정 —
    /// caller가 `preservedPayload`로 게이트) 문단 placeholder의
    /// `unknownChildren` 보존과 대칭인 진단·재파싱 근거를 남긴다.
    static func parseFailurePlaceholder(
        error: HwpError,
        rawPayload: Data = Data()
    ) -> HwpSection {
        var section = HwpSection()
        section.rawPayload = rawPayload
        section.parseFailure = String(describing: error)
        return section
    }

    // MARK: loader contract exemption - BodyText section stream must be parsed as one record tree

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let records = try parseTreeRecord(data: try reader.readToEnd(), options: reader.options)
        var paragraphs = [HwpParagraph]()
        var unknownRecords = [HwpUnknownRecord]()

        for record in records.children {
            if record.tagId == HwpSectionTag.paraHeader.rawValue {
                // 복구 모드에서는 손상 문단 하나가 구역 전체(→ 문서 전체)를
                // 실패시키지 않도록 placeholder로 대체한다. 자원 한도 등
                // recovery-exempt 오류는 계속 전파한다 (#65).
                //
                // 단 구역의 첫 문단은 예외다 — sectionDef는 첫 문단에만 붙으므로
                // (blankDocumentParagraph 참조) 이를 sectionDef 없는 문단
                // placeholder로 삼키면 paginator가 구역 경계를 인식하지 못해 그
                // 구역이 앞 구역의 지오메트리로 조판된다. 첫 문단 손상은 전파해
                // HwpFile이 구역 단위 placeholder(sectionDef 보존)로 승격시킨다 (#110).
                do {
                    paragraphs.append(try HwpParagraph.load(record, version))
                } catch let error as HwpError
                    where !paragraphs.isEmpty
                    && reader.options.recoverPartialContent && !error.isRecoveryExempt
                {
                    paragraphs.append(.parseFailurePlaceholder(record: record, error: error))
                }
            } else {
                unknownRecords.append(HwpUnknownRecord(record))
            }
        }

        guard !paragraphs.isEmpty else {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.paraHeader.rawValue)
        }

        paragraph = paragraphs
        self.unknownRecords = unknownRecords
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - raw section payload is restored after record-tree parse

    public static func load(
        _ data: Data,
        _ version: HwpVersion,
        options: HwpLoadOptions = .default
    ) throws -> Self {
        // 유일한 public 파싱 진입점이다. `HwpFile` 이니셜라이저와 달리 여기로는
        // 검증되지 않은 한도가 그대로 들어오므로, 비-양수 한도를 "모든 레코드가
        // 거부됨"이 아니라 typed 진단으로 돌려준다.
        try options.readLimits.validate()
        var reader = DataReader(data, options: options)
        var section = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        section.rawPayload = options.preservedPayload(data)
        return section
    }
}
