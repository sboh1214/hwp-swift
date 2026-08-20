@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 섹션 byte 스트림의 **중첩 위치** 레벨/확장 크기 조작이 public 진입점
/// `HwpSection.load`를 통과하며 typed error로 전파됨을 고정한다 (#67).
///
/// 루트 수준의 같은 조작은 `RecordParserStabilityTests`가 커버한다 — 여기의
/// 목적은 정상 레코드 뒤 중첩 위치에서의 전파 경로와, 구역 스트림 구조
/// 손상이 recover 모드(`.viewer`)에서도 똑같이 throw된다는 시맨틱이다
/// (구역 단위 복구는 `HwpFile` 조립의 몫이다, #65).
final class SectionNestedAdversarialTests: XCTestCase {
    private let version = HwpVersion(5, 0, 1, 1)
    private let bothModes = [HwpLoadOptions.default, .viewer]

    func testNestedLevelJumpThrowsTypedErrorThroughSectionLoad() {
        // paraHeader(0) → charShape(1) 뒤 level 3: 스택 [root, para, charShape]
        // 밖의 점프라 부모가 없다.
        var data = nestedAdversarialValidParagraphData()
        data.append(SectionRecordBuilder.record(tagId: 0x2FE, level: 3, payload: Data([0xAA])))

        for options in bothModes {
            expect {
                _ = try HwpSection.load(data, self.version, options: options)
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("record level 3 has no parent"))
            })
        }
    }

    func testLevelRetreatOrphanChildThrowsTypedErrorThroughSectionLoad() {
        // level 1까지 갔다가 level 0으로 후퇴하면 스택이 [root, 0x2FE]로
        // 잘린다 — 그 뒤의 level 2는 이전 깊이의 고아 자식이라 부모가 없다.
        var data = nestedAdversarialValidParagraphData()
        data.append(SectionRecordBuilder.record(tagId: 0x2FE, level: 0, payload: Data([0xBB])))
        data.append(SectionRecordBuilder.record(tagId: 0x2FD, level: 2, payload: Data([0xCC])))

        for options in bothModes {
            expect {
                _ = try HwpSection.load(data, self.version, options: options)
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("record level 2 has no parent"))
            })
        }
    }

    func testNestedOversizedExtendedRecordThrowsTypedErrorWithoutAllocation() {
        // 중첩 위치의 0xFFF 확장 크기 + UInt32.max 선언 — 무할당 typed 거부가
        // 정상 레코드 뒤에서도 유지되는지 (회귀 보험).
        var data = nestedAdversarialValidParagraphData()
        data.append(SectionRecordBuilder.header(tagId: 0x2FE, level: 1, size: 0xFFF))
        data.append(SectionRecordBuilder.littleEndian(UInt32.max))
        data.append(0xAA)

        for options in bothModes {
            expect {
                _ = try HwpSection.load(data, self.version, options: options)
            }.to(throwError { error in
                guard case let HwpError.truncatedData(expected, actual) = error else {
                    return fail("Expected truncatedData, got \(error)")
                }
                expect(expected) == Int(UInt32.max)
                expect(actual) == 1
            })
        }
    }

    func testNestedTruncatedExtendedSizeWordThrowsTypedErrorThroughSectionLoad() {
        // 0xFFF sentinel 뒤 실제 크기 UInt32가 잘린 스트림 꼬리.
        var data = nestedAdversarialValidParagraphData()
        data.append(SectionRecordBuilder.header(tagId: 0x2FE, level: 1, size: 0xFFF))
        data.append(contentsOf: [0x01, 0x02])

        for options in bothModes {
            expect {
                _ = try HwpSection.load(data, self.version, options: options)
            }.to(throwError { error in
                guard case let HwpError.truncatedData(expected, actual) = error else {
                    return fail("Expected truncatedData, got \(error)")
                }
                expect(expected) == 4
                expect(actual) == 2
            })
        }
    }
}

private func nestedAdversarialValidParagraphData() -> Data {
    var data = SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: nestedAdversarialParaHeaderPayload()
    )
    data.append(SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: Data()
    ))
    return data
}

private func nestedAdversarialParaHeaderPayload() -> Data {
    var data = Data()
    data.append(SectionRecordBuilder.littleEndian(UInt32(0x8000_0000)))
    data.append(SectionRecordBuilder.littleEndian(UInt32(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt8(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt8(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt16(0)))
    data.append(SectionRecordBuilder.littleEndian(UInt32(1)))
    return data
}
