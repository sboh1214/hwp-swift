@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 컨트롤 폴백 허용 error 집합의 스펙 고정 (#67).
///
/// `HwpParagraph.swift`의 `canFallbackToRaw*` 세 판정은 `private extension`이라
/// 직접 호출로 단언할 수 없다 — 손상 입력의 **동작 경유**로 집합을 고정한다.
/// 이 표가 스펙이다. 폴백 집합을 바꾸면 이 파일이 함께 바뀌어야 한다 (의도된
/// 고정).
///
/// | 판정 (소비처) | 허용 → 폴백 | 불허 → 전파 (대표) |
/// |---|---|---|
/// | `canFallbackToRawControl` (표·하이퍼링크·단·구역정의·쪽번호) |
///   truncatedData, invalidUnicodeScalar, invalidRawValueForEnum |
///   recordDoesNotExist, invalidRecordTree, bytesAreNotEOF |
/// | `canFallbackToRawListControl` (머리말·꼬리말·각주·미주→other) |
///   위 base + recordDoesNotExist, invalidRecordTree | bytesAreNotEOF |
/// | `canFallbackToRawGenShapeObject` (gso·공통 도형→notImplemented) |
///   위 base + invalidRecordTree | recordDoesNotExist, bytesAreNotEOF |
///
/// 개별 폴백 사례의 상세 단언은 `Controls/` 스위트가 맡는다
/// (`TableControlStabilityTests`·`ListControlStabilityTests`·
/// `ShapeComponentTextBoxStabilityTests`) — 여기서는 집합 경계만 고정한다.
final class ControlFallbackErrorSetSpecTests: XCTestCase {
    private let version = HwpVersion(5, 0, 1, 1)

    // MARK: - canFallbackToRawControl (표 계열)

    func testTableTruncatedDataIsInFallbackSet() throws {
        // truncatedData ∈ canFallbackToRawControl → notImplemented 보존.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecLittleEndianData(HwpCommonCtrlId.table.rawValue),
            children: []
        )

        let paragraph = try HwpParagraph.load(
            fallbackSpecHostParagraphRecord(control: record),
            version
        )

        guard case .notImplemented = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated table control to fall back to notImplemented")
        }
    }

    func testTableRecordDoesNotExistIsOutOfFallbackSet() {
        // recordDoesNotExist ∉ canFallbackToRawControl → 전파 (표 75 레코드 부재).
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecCommonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue),
            children: []
        )

        expect {
            _ = try HwpParagraph.load(
                fallbackSpecHostParagraphRecord(control: record),
                self.version
            )
        }.to(throwError { error in
            guard case let HwpError.recordDoesNotExist(tag) = error else {
                return fail("Expected recordDoesNotExist, got \(error)")
            }
            expect(tag) == HwpSectionTag.table.rawValue
        })
    }

    func testTableNestedBytesAreNotEOFIsOutOfFallbackSet() {
        // bytesAreNotEOF ∉ canFallbackToRawControl → 셀 문단 깊이에서도 전파.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecCommonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.table.rawValue,
                    level: 2,
                    payload: fallbackSpecTablePropertyPayload(rowCount: 1, columnCount: 1)
                ),
                HwpRecord(
                    tagId: HwpSectionTag.listHeader.rawValue,
                    level: 2,
                    payload: fallbackSpecTableCellHeaderPayload(paragraphCount: 1)
                ),
                fallbackSpecCorruptRangeTagParagraphRecord(level: 2),
            ]
        )

        expectFallbackSpecRangeTagBytesAreNotEOF {
            _ = try HwpParagraph.load(
                fallbackSpecHostParagraphRecord(control: record),
                self.version
            )
        }
    }

    // MARK: - canFallbackToRawListControl (머리말 계열)

    func testListControlNegativeCountInvalidRecordTreeIsInFallbackSet() throws {
        // invalidRecordTree ∈ canFallbackToRawListControl → other 보존.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecLittleEndianData(HwpOtherCtrlId.header.rawValue),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.listHeader.rawValue,
                    level: 2,
                    payload: fallbackSpecListHeaderPayload(paragraphCount: -1)
                ),
            ]
        )

        let paragraph = try HwpParagraph.load(
            fallbackSpecHostParagraphRecord(control: record),
            version
        )

        guard case let .other(other) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected negative-count list control to fall back to other")
        }
        expect(other.ctrlId) == .header
    }

    func testListControlMissingListHeaderRecordDoesNotExistIsInFallbackSet() throws {
        // recordDoesNotExist ∈ canFallbackToRawListControl → other 보존.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecLittleEndianData(HwpOtherCtrlId.header.rawValue),
            children: [
                HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xAA])),
            ]
        )

        let paragraph = try HwpParagraph.load(
            fallbackSpecHostParagraphRecord(control: record),
            version
        )

        guard case let .other(other) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected list control without LIST_HEADER to fall back to other")
        }
        expect(other.ctrlId) == .header
    }

    func testListControlNestedBytesAreNotEOFIsOutOfFallbackSet() {
        // bytesAreNotEOF ∉ canFallbackToRawListControl → 리스트 문단 깊이에서도 전파.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecLittleEndianData(HwpOtherCtrlId.header.rawValue),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.listHeader.rawValue,
                    level: 2,
                    payload: fallbackSpecListHeaderPayload(paragraphCount: 1)
                ),
                fallbackSpecCorruptRangeTagParagraphRecord(level: 2),
            ]
        )

        expectFallbackSpecRangeTagBytesAreNotEOF {
            _ = try HwpParagraph.load(
                fallbackSpecHostParagraphRecord(control: record),
                self.version
            )
        }
    }

    // MARK: - canFallbackToRawGenShapeObject (gso 계열)

    func testGenShapeObjectInvalidRecordTreeIsInFallbackSet() throws {
        // invalidRecordTree ∈ canFallbackToRawGenShapeObject → notImplemented 보존.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecCommonCtrlPropertyPayload(
                ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
            ),
            children: [
                fallbackSpecShapeComponentRecord(children: [
                    HwpRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: fallbackSpecListHeaderPayload(paragraphCount: -1)
                    ),
                ]),
            ]
        )

        let paragraph = try HwpParagraph.load(
            fallbackSpecHostParagraphRecord(control: record),
            version
        )

        guard case .notImplemented = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected corrupt text-box gso to fall back to notImplemented")
        }
    }

    func testGenShapeObjectRecordDoesNotExistIsOutOfFallbackSet() {
        // recordDoesNotExist ∉ canFallbackToRawGenShapeObject → 전파
        // (글상자 문단의 필수 PARA_CHAR_SHAPE 부재).
        let textBoxParagraph = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 3,
            payload: fallbackSpecParagraphHeaderPayload()
        )
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecCommonCtrlPropertyPayload(
                ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
            ),
            children: [
                fallbackSpecShapeComponentRecord(children: [
                    HwpRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: fallbackSpecListHeaderPayload(paragraphCount: 1)
                    ),
                    textBoxParagraph,
                ]),
            ]
        )

        expect {
            _ = try HwpParagraph.load(
                fallbackSpecHostParagraphRecord(control: record),
                self.version
            )
        }.to(throwError { error in
            guard case let HwpError.recordDoesNotExist(tag) = error else {
                return fail("Expected recordDoesNotExist, got \(error)")
            }
            expect(tag) == HwpSectionTag.paraCharShape.rawValue
        })
    }

    func testGenShapeObjectNestedBytesAreNotEOFIsOutOfFallbackSet() {
        // bytesAreNotEOF ∉ canFallbackToRawGenShapeObject → 글상자 문단
        // 깊이에서도 전파.
        let record = fallbackSpecCtrlRecord(
            payload: fallbackSpecCommonCtrlPropertyPayload(
                ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
            ),
            children: [
                fallbackSpecShapeComponentRecord(children: [
                    HwpRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: fallbackSpecListHeaderPayload(paragraphCount: 1)
                    ),
                    fallbackSpecCorruptRangeTagParagraphRecord(level: 3),
                ]),
            ]
        )

        expectFallbackSpecRangeTagBytesAreNotEOF {
            _ = try HwpParagraph.load(
                fallbackSpecHostParagraphRecord(control: record),
                self.version
            )
        }
    }
}

// MARK: - 공통 빌더/단언

private func expectFallbackSpecRangeTagBytesAreNotEOF(
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
            return fail("Expected bytesAreNotEOF, got \(error)")
        }
        expect(String(describing: model)) == "HwpParaRangeTag"
        expect(remain) == 1
    })
}

private func fallbackSpecCtrlRecord(payload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: payload
    )
    record.children = children
    return record
}

private func fallbackSpecShapeComponentRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: fallbackSpecLittleEndianData(HwpCommonCtrlId.rectangle.rawValue)
    )
    record.children = children
    return record
}

private func fallbackSpecHostParagraphRecord(control: HwpRecord) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: fallbackSpecParagraphHeaderPayload()
    )
    record.children = [
        HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
        HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
        control,
    ]
    return record
}

/// PARA_RANGE_TAG 12 byte 엔트리 뒤 1 byte 꼬리 → `HwpParaRangeTag.loadArray`가
/// bytesAreNotEOF(remain 1)를 던지는 손상 문단 (레코드 자식으로 중첩시킨다).
private func fallbackSpecCorruptRangeTagParagraphRecord(level: UInt32) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: level,
        payload: fallbackSpecParagraphHeaderPayload()
    )
    record.children = [
        HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: level + 1, payload: Data()),
        HwpRecord(
            tagId: HwpSectionTag.paraRangeTag.rawValue,
            level: level + 1,
            payload: concatenatedData(
                fallbackSpecLittleEndianData(UInt32(1)),
                fallbackSpecLittleEndianData(UInt32(9)),
                fallbackSpecLittleEndianData(UInt32(0xABCD)),
                Data([0xFF])
            )
        ),
    ]
    return record
}

private func fallbackSpecParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(fallbackSpecLittleEndianData(UInt32(0x8000_0000)))
    data.append(fallbackSpecLittleEndianData(UInt32(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(fallbackSpecLittleEndianData(UInt8(0)))
    data.append(fallbackSpecLittleEndianData(UInt8(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(fallbackSpecLittleEndianData(UInt32(1)))
    return data
}

/// 개체 공통 속성 (표 70) 전체가 유효한 payload — 절단 truncatedData 폴백이
/// 뒤의 out-of-set 오류를 가리지 않게 한다.
private func fallbackSpecCommonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(fallbackSpecLittleEndianData(ctrlId))
    data.append(fallbackSpecLittleEndianData(UInt32(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT(0)))
    data.append(fallbackSpecLittleEndianData(Int32(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(UInt32(0)))
    data.append(fallbackSpecLittleEndianData(Int32(0)))
    data.append(fallbackSpecLittleEndianData(WORD(0)))
    return data
}

private func fallbackSpecTablePropertyPayload(rowCount: UInt16, columnCount: UInt16) -> Data {
    var data = Data()
    data.append(fallbackSpecLittleEndianData(UInt32(0)))
    data.append(fallbackSpecLittleEndianData(rowCount))
    data.append(fallbackSpecLittleEndianData(columnCount))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    data.append(fallbackSpecLittleEndianData(HWPUNIT16(0)))
    for _ in 0 ..< rowCount {
        data.append(fallbackSpecLittleEndianData(UInt16(0)))
    }
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    return data
}

private func fallbackSpecTableCellHeaderPayload(paragraphCount: UInt16) -> Data {
    var data = Data()
    data.append(fallbackSpecLittleEndianData(paragraphCount))
    data.append(fallbackSpecLittleEndianData(UInt32(0)))
    data.append(fallbackSpecLittleEndianData(UInt16(0)))
    data.append(Data(repeating: 0, count: 39))
    return data
}

private func fallbackSpecListHeaderPayload(paragraphCount: Int32) -> Data {
    concatenatedData(
        fallbackSpecLittleEndianData(paragraphCount),
        fallbackSpecLittleEndianData(UInt32(0))
    )
}

private func fallbackSpecLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
