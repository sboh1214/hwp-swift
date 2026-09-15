@testable import CoreHwp
import Nimble
import XCTest

/// 구역 시작 종류(표 130 bits 20-21)와 첫 쪽 번호 규칙 (#185). 값의 근거는
/// `section-page-starts-on`·`section-page-number-skip` 쌍과 한글 12.30 PDF 실측이다.
final class HwpSectionPageStartsOnTests: XCTestCase {
    func testPageStartsOnReadsBits20To21AndLeavesUndefinedRawValueNil() throws {
        // 한글 저장본: 홀수 0x200000(2) · 짝수 0x100000(1) · 이어서 0.
        expect(try HwpSectionDefProperty.load(0x0020_0000).pageStartsOn) == .odd
        expect(try HwpSectionDefProperty.load(0x0010_0000).pageStartsOn) == .even
        expect(try HwpSectionDefProperty.load(0).pageStartsOn) == .both
        // raw 3은 정의되지 않은 값 — 파생 필드는 3, 종류는 nil.
        let undefined = try HwpSectionDefProperty.load(0x0030_0000)
        expect(undefined.newPageNumberApplyRawValue) == 3
        expect(undefined.pageStartsOn).to(beNil())
    }

    func testFirstPageNumberSkipsOnlyMismatchedParity() throws {
        // 이어서 → 그대로.
        expect(try Self.sectionDef(property: 0).firstPageNumber(continuing: 2)) == 2
        // 홀수 시작: 짝수 번호만 1 건너뛴다 (2 → 3), 홀수는 그대로 (7 → 7).
        expect(try Self.sectionDef(property: 0x0020_0000).firstPageNumber(continuing: 2)) == 3
        expect(try Self.sectionDef(property: 0x0020_0000).firstPageNumber(continuing: 7)) == 7
        // 짝수 시작: 홀수 번호만 1 건너뛴다 (5 → 6), 짝수는 그대로 (4 → 4).
        expect(try Self.sectionDef(property: 0x0010_0000).firstPageNumber(continuing: 5)) == 6
        expect(try Self.sectionDef(property: 0x0010_0000).firstPageNumber(continuing: 4)) == 4
        // 문서 첫 구역(이어지는 번호 1)도 같다 — 짝수 시작 첫 쪽은 2, 홀수 시작은 1.
        expect(try Self.sectionDef(property: 0x0010_0000).firstPageNumber(continuing: 1)) == 2
        expect(try Self.sectionDef(property: 0x0020_0000).firstPageNumber(continuing: 1)) == 1
        // 정의되지 않은 raw 3은 이어서로 다룬다.
        expect(try Self.sectionDef(property: 0x0030_0000).firstPageNumber(continuing: 2)) == 2
    }

    func testUserPageStartNumberWinsOverParity() throws {
        // 한글 12.30: ODD + page 4 → 4, EVEN + page 7 → 7 (종류를 보지 않는다).
        let oddFour = try Self.sectionDef(property: 0x0020_0000, pageStartNumber: 4)
        expect(oddFour.firstPageNumber(continuing: 2)) == 4
        let evenSeven = try Self.sectionDef(property: 0x0010_0000, pageStartNumber: 7)
        expect(evenSeven.firstPageNumber(continuing: 5)) == 7
        let userNine = try Self.sectionDef(property: 0, pageStartNumber: 9)
        expect(userNine.firstPageNumber(continuing: 8)) == 9
    }

    func testRealPairsCarryTheExpectedStartKinds() throws {
        let startsOn = try HwpFile(
            fromPath: FixtureLoader.load(id: "section-page-starts-on").documentURL.path
        )
        expect(Self.startKinds(of: startsOn)) == [.both, .odd, .even, .both]
        let skip = try HwpFile(
            fromPath: FixtureLoader.load(id: "section-page-number-skip").documentURL.path
        )
        expect(Self.startKinds(of: skip)) == [.both, .odd, .even, .even, .odd, .both, .both]
        // 같은 문서의 첫 쪽 번호를 이어 붙이면 한글 PDF의 1·3·4·6·7·9·10이 된다.
        var numbers: [Int] = []
        var next = 1
        for sectionDef in Self.sectionDefs(of: skip) {
            let first = sectionDef.firstPageNumber(continuing: next)
            numbers.append(first)
            next = first + 1
        }
        expect(numbers) == [1, 3, 4, 6, 7, 9, 10]
    }
}

private extension HwpSectionPageStartsOnTests {
    static func sectionDef(property: UInt32, pageStartNumber: UInt16 = 0) throws -> HwpSectionDef {
        var sectionDef = HwpSectionDef()
        sectionDef.property = property
        sectionDef.propertyInfo = try HwpSectionDefProperty.load(property)
        sectionDef.pageStartNumber = pageStartNumber
        return sectionDef
    }

    static func sectionDefs(of hwp: HwpFile) -> [HwpSectionDef] {
        hwp.sectionArray.compactMap { section in
            section.paragraph.first?.ctrlHeaderArray?.compactMap { ctrl -> HwpSectionDef? in
                if case let .section(sectionDef) = ctrl {
                    return sectionDef
                }
                return nil
            }.first
        }
    }

    static func startKinds(of hwp: HwpFile) -> [HwpSectionPageStartsOn?] {
        sectionDefs(of: hwp).map(\.propertyInfo.pageStartsOn)
    }
}
