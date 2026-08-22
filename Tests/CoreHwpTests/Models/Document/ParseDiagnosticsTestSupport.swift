@testable import CoreHwp
import Foundation

// `ParseDiagnosticsTests`/`ParseDiagnosticsRecoveryTests`가 공유하는 합성
// 스트림 빌더 (#66). 레코드 프레이밍은 SectionRecordBuilder가 단일 출처다.

/// 최상위 unknown record(+child), unknown 컨트롤(+child), 문단 unknown
/// child(+child)를 모두 가진 구역 스트림.
func diagnosticsUnknownHeavySectionData() -> Data {
    var data = diagnosticsRecord(tagId: 0x2FE, level: 0, payload: Data([0xCA]))
    data.append(diagnosticsRecord(tagId: 0x2FD, level: 1, payload: Data([0xAB])))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: diagnosticsParaHeaderPayload()
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: diagnosticsLittleEndianData(UInt32(0x5858_5858))
    ))
    data.append(diagnosticsRecord(tagId: 0x2FC, level: 2, payload: Data([0x01])))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
    ))
    data.append(diagnosticsRecord(tagId: 0x2FB, level: 1, payload: Data([0x02])))
    data.append(diagnosticsRecord(tagId: 0x2FA, level: 2, payload: Data([0x03])))
    return data
}

/// 정상 문단 하나 + 최상위 unknown record 하나를 가진 최소 구역 스트림.
func diagnosticsSectionData(unknownTagId: UInt32) -> Data {
    var data = diagnosticsRecord(tagId: unknownTagId, level: 0, payload: Data([0x77]))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: diagnosticsParaHeaderPayload()
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
    ))
    return data
}

/// [정상 문단, 손상 문단(문단 placeholder), 메모 호스트(손상 메모 문단 포함)]
/// 구역 — 복구 모드에서 recoveredParagraph·recoveredMemoParagraph를 만든다.
func diagnosticsRecoverySectionData() -> Data {
    var data = diagnosticsValidParagraphData(level: 0)
    data.append(diagnosticsCorruptParagraphData(level: 0))

    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: diagnosticsParaHeaderPayload()
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()
    ))
    data.append(diagnosticsMemoParagraphData(level: 1))
    data.append(diagnosticsCorruptParagraphData(level: 1))
    return data
}

/// 레코드 트리 구조 자체가 깨진 구역 — HwpFile 조립이 구역 단위 placeholder로
/// 승격한다 (`record level 2 has no parent`).
func diagnosticsCorruptSectionData() -> Data {
    diagnosticsRecord(tagId: 0x2FE, level: 2, payload: Data([0xAA]))
}

func diagnosticsValidParagraphData(level: UInt32) -> Data {
    var data = diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: level,
        payload: diagnosticsParaHeaderPayload(charCount: 1, charShapeInfoCount: 1)
    )
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraText.rawValue,
        level: level + 1,
        payload: diagnosticsLittleEndianData(WCHAR(0xAC00))
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: level + 1,
        payload: diagnosticsCharShapePairPayload()
    ))
    return data
}

func diagnosticsMemoParagraphData(level: UInt32) -> Data {
    var data = diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: level,
        payload: diagnosticsParaHeaderPayload()
    )
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: level + 1, payload: Data()
    ))
    return data
}

/// charShapeInfoCount(2)와 실제 PARA_CHAR_SHAPE 항목 수(1)가 어긋난 손상 문단.
func diagnosticsCorruptParagraphData(level: UInt32) -> Data {
    var data = diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: level,
        payload: diagnosticsParaHeaderPayload(charShapeInfoCount: 2)
    )
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: level + 1,
        payload: diagnosticsCharShapePairPayload()
    ))
    return data
}

/// PARA_HEADER payload (HwpFileHeader() 기본 5.1.0.1 — 5.0.3.2 이상 24 byte).
func diagnosticsParaHeaderPayload(
    charCount: UInt32 = 0,
    charShapeInfoCount: UInt16 = 0
) -> Data {
    var data = Data()
    data.append(diagnosticsLittleEndianData(charCount | 0x8000_0000))
    data.append(diagnosticsLittleEndianData(UInt32(0)))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    data.append(diagnosticsLittleEndianData(UInt8(0)))
    data.append(diagnosticsLittleEndianData(UInt8(0)))
    data.append(diagnosticsLittleEndianData(charShapeInfoCount))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    data.append(diagnosticsLittleEndianData(UInt32(1)))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    return data
}

func diagnosticsCharShapePairPayload() -> Data {
    concatenatedData(
        diagnosticsLittleEndianData(UInt32(0)),
        diagnosticsLittleEndianData(UInt32(0))
    )
}

/// 1×1 표 컨트롤 안에 unknown record와 unknown 컨트롤을 가진 셀 문단을 심은
/// 구역 스트림 — 셀 path 재귀 검증용.
func diagnosticsTableSectionData() -> Data {
    var cellParagraph = diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 2,
        payload: diagnosticsParaHeaderPayload()
    )
    cellParagraph.append(diagnosticsRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 3,
        payload: diagnosticsLittleEndianData(UInt32(0x5959_5959))
    ))
    cellParagraph.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 3, payload: Data()
    ))

    var data = diagnosticsRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: diagnosticsParaHeaderPayload()
    )
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: diagnosticsTableCommonCtrlPropertyPayload()
    ))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.table.rawValue,
        level: 2,
        payload: diagnosticsTablePropertyPayload(rowCount: 1, columnCount: 1)
    ))
    data.append(diagnosticsRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])))
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 2,
        payload: diagnosticsTableCellHeaderPayload(paragraphCount: 1)
    ))
    data.append(cellParagraph)
    data.append(diagnosticsRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
    ))
    return data
}

/// 표 컨트롤 CTRL_HEADER payload — 개체 공통 속성 46 byte
/// (`TableControlStabilityTests`의 레이아웃과 동일).
func diagnosticsTableCommonCtrlPropertyPayload() -> Data {
    var data = Data()
    data.append(diagnosticsLittleEndianData(HwpCommonCtrlId.table.rawValue))
    data.append(diagnosticsLittleEndianData(UInt32(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT(0)))
    data.append(diagnosticsLittleEndianData(Int32(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(UInt32(0)))
    data.append(diagnosticsLittleEndianData(Int32(0)))
    data.append(diagnosticsLittleEndianData(WORD(0)))
    return data
}

func diagnosticsTablePropertyPayload(rowCount: UInt16, columnCount: UInt16) -> Data {
    var data = Data()
    data.append(diagnosticsLittleEndianData(UInt32(0)))
    data.append(diagnosticsLittleEndianData(rowCount))
    data.append(diagnosticsLittleEndianData(columnCount))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    data.append(diagnosticsLittleEndianData(HWPUNIT16(0)))
    for _ in 0 ..< rowCount {
        data.append(diagnosticsLittleEndianData(UInt16(0)))
    }
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    return data
}

func diagnosticsTableCellHeaderPayload(paragraphCount: UInt16) -> Data {
    var data = Data()
    data.append(diagnosticsLittleEndianData(paragraphCount))
    data.append(diagnosticsLittleEndianData(UInt32(0)))
    data.append(diagnosticsLittleEndianData(UInt16(0)))
    data.append(Data(repeating: 0, count: 39))
    return data
}

/// HwpFile 조립 최소 DocInfo — 필요하면 최상위 unknown record(+child)를 심는다.
func diagnosticsDocInfoData(
    sectionSize: UInt16,
    includeUnknownRecord: Bool = false
) -> Data {
    var data = concatenatedData(
        diagnosticsRecord(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: concatenatedData(
                diagnosticsLittleEndianData(sectionSize),
                Data(repeating: 0, count: 24)
            )
        ),
        diagnosticsRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
                data.append(diagnosticsLittleEndianData(count))
            }
        )
    )
    if includeUnknownRecord {
        data.append(diagnosticsRecord(tagId: 0x2F9, level: 0, payload: Data([0x11])))
        data.append(diagnosticsRecord(tagId: 0x2F8, level: 1, payload: Data([0x22])))
    }
    return data
}

func diagnosticsRecord(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    SectionRecordBuilder.record(tagId: tagId, level: level, payload: payload)
}

func diagnosticsLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    SectionRecordBuilder.littleEndian(value)
}
