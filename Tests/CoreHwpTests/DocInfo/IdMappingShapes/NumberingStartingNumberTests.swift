@testable import CoreHwp
import Nimble
import XCTest

/// 문단 번호 정의의 시작 번호 해석 (#153) — 시작 번호 방식(`continuesPreviousList`)과
/// 수준별 시작 번호(`startingNumber(forLevel:)`). 실물은 헌법주석(5.0.2.2, 수준별
/// 배열 없음·정의 41개)과 한글.app 12.30 저장본(`outline-numbering`)이다.
final class NumberingStartingNumberTests: XCTestCase {
    private static func definition(
        startingIndex: UInt16,
        startingIndexArray: [UInt32]? = nil,
        extendedStartingIndexArray: [UInt32]? = nil
    ) -> HwpNumbering {
        HwpNumbering(
            formatArray: [],
            startingIndex: startingIndex,
            startingIndexArray: startingIndexArray,
            extendedStartingIndexArray: extendedStartingIndexArray
        )
    }

    /// 헌법주석 — 41개 구역이 하나씩 가리키는 41개 정의 중 첫 구역 것만 이어
    /// 매기기(0)이고 나머지 40개는 새 번호(1)다. 5.0.2.2 저장본이라 수준별 배열이
    /// 없고, 그런 정의의 시작 번호는 전 수준 1이다.
    func testLegacyDefinitionsSplitIntoOneContinuationAndFortyRestarts() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let definitions = hwp.docInfo.idMappings.numberingArray
        expect(definitions.count) == 41
        expect(definitions.first?.continuesPreviousList) == true
        expect(definitions.map(\.startingIndex)) == [0] + Array(repeating: 1, count: 40)
        expect(definitions.allSatisfy { $0.startingIndexArray == nil }) == true
        expect(definitions.allSatisfy { $0.extendedStartingIndexArray == nil }) == true
        for definition in definitions {
            expect((1 ... 10).map { definition.startingNumber(forLevel: $0) })
                == Array(repeating: 1, count: 10)
        }
    }

    /// 한글.app 12.30 저장본 — 정의 전체 시작 번호 0(이어 매기기), 수준별 1.
    func testHancomSavedDefinitionsContinueWithLevelStartsOfOne() throws {
        for hwp in [
            try openHwp(#file, "outline-numbering"), try openHwpx(#file, "outline-numbering"),
        ] {
            for definition in hwp.docInfo.idMappings.numberingArray {
                expect(definition.continuesPreviousList) == true
                expect(definition.startingIndexArray) == Array(repeating: 1, count: 7)
                expect(definition.extendedStartingIndexArray) == [1, 1, 1]
                expect((1 ... 10).map { definition.startingNumber(forLevel: $0) })
                    == Array(repeating: 1, count: 10)
            }
        }
    }

    /// 수준별 값이 있으면 그 값, 없거나 0이면 1이다. 확장 수준(8-10)은 확장 배열.
    func testPerLevelStartsFallBackToOne() {
        let numbering = Self.definition(
            startingIndex: 0,
            startingIndexArray: [3, 0, 7],
            extendedStartingIndexArray: [0, 9]
        )
        expect((1 ... 10).map { numbering.startingNumber(forLevel: $0) })
            == [3, 1, 7, 1, 1, 1, 1, 1, 9, 1]
        expect(Self.definition(startingIndex: 0).startingNumber(forLevel: 4)) == 1
        expect(numbering.startingNumber(forLevel: 0)) == 1
        expect(numbering.startingNumber(forLevel: 11)) == 1
    }

    /// 수준별 배열이 있으면 배열이 이긴다 — 한글.app이 목록의 모양을 바꾸면 배열만
    /// 1로 되돌리고 `startingIndex`에 옛 새 번호를 남기는데 화면은 1부터다
    /// (`numbering-sequence` 정의 3: `start=5`, 배열 [1, …] → `1.`). 배열이 없는
    /// 저장본에서만 `startingIndex`가 1수준 시작 번호다.
    func testLevelOneFollowsThePerLevelArrayWhenPresent() {
        func levelOne(_ startingIndex: UInt16, _ array: [UInt32]? = nil) -> Int {
            Self.definition(startingIndex: startingIndex, startingIndexArray: array)
                .startingNumber(forLevel: 1)
        }
        expect(levelOne(5, [1, 1])) == 1
        expect(levelOne(1, [5, 1])) == 5
        expect(levelOne(5, [5, 1])) == 5
        expect(levelOne(5, [0, 1])) == 1
        expect(levelOne(5)) == 5
        expect(levelOne(0)) == 1
        expect(Self.definition(startingIndex: 5).startingNumber(forLevel: 2)) == 1
        expect(
            Self.definition(startingIndex: 5, startingIndexArray: [1, 4]).startingNumber(forLevel: 2)
        ) == 4
        expect(Self.definition(startingIndex: 1).continuesPreviousList) == false
        expect(Self.definition(startingIndex: 5).continuesPreviousList) == false
    }

    /// 한글.app 12.30이 저장한 `numbering-sequence` 쌍의 정의 6개 — 새 번호 N은
    /// `startingIndex`와 배열의 첫 값에 함께 적히고(7·9), 구역 나누기가 만든 정의와
    /// 문단 번호 적용이 만든 정의는 0(이어 매기기)이다.
    func testHancomSequenceFixtureStoresNewNumbersInBothFields() throws {
        for hwp in [
            try openHwp(#file, "numbering-sequence"), try openHwpx(#file, "numbering-sequence"),
        ] {
            let definitions = hwp.docInfo.idMappings.numberingArray
            expect(definitions.map(\.startingIndex)) == [0, 0, 5, 0, 7, 9]
            expect(definitions.map { $0.startingIndexArray?.first }) == [1, 1, 1, 1, 7, 9]
            expect(definitions.map(\.continuesPreviousList)) == [
                true, true, false, true, false, false,
            ]
            expect(definitions.map { $0.startingNumber(forLevel: 1) }) == [1, 1, 1, 1, 7, 9]
        }
    }

    /// 수준별 값은 UINT32지만 65,535로 접는다 — 정의 전체 시작 번호(UINT16)와 한글의
    /// 새 번호 입력 상한이 그 값이고, 그 위는 로마 숫자 라벨 길이를 키우는 조작이다.
    func testStartingNumbersAreClampedToTheSixteenBitCeiling() {
        let numbering = Self.definition(
            startingIndex: 0,
            startingIndexArray: [UInt32.max, 65536, 65535],
            extendedStartingIndexArray: [70000]
        )
        expect((1 ... 3).map { numbering.startingNumber(forLevel: $0) }) == [65535, 65535, 65535]
        expect(numbering.startingNumber(forLevel: 8)) == 65535
        expect(Self.definition(startingIndex: UInt16.max).startingNumber(forLevel: 1)) == 65535
    }
}
