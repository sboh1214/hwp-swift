@testable import CoreHwp
import Nimble
import XCTest

/// 문단 번호 정의의 시작 번호 해석 (#153) — 시작 번호 방식(`continuesPreviousList`)과
/// 수준별 시작 번호(`startingNumber(forLevel:)`). 실물은 헌법주석(5.0.2.2, 수준별
/// 배열 없음·정의 54개)과 한글.app 12.30 저장본(`outline-numbering`)이다.
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

    /// 1수준은 정의 전체 시작 번호와 수준별 값 중 큰 쪽이다 — 새 번호 N이 어느
    /// 자리에 적혀도 같은 결과다. 2수준부터는 정의 전체 값을 보지 않는다.
    func testLevelOneTakesTheLargerOfTheTwoStartFields() {
        func levelOne(_ startingIndex: UInt16, _ array: [UInt32]? = nil) -> Int {
            Self.definition(startingIndex: startingIndex, startingIndexArray: array)
                .startingNumber(forLevel: 1)
        }
        expect(levelOne(5, [1, 1])) == 5
        expect(levelOne(1, [5, 1])) == 5
        expect(levelOne(5, [5, 1])) == 5
        expect(levelOne(5)) == 5
        expect(Self.definition(startingIndex: 5).startingNumber(forLevel: 2)) == 1
        expect(
            Self.definition(startingIndex: 5, startingIndexArray: [1, 4]).startingNumber(forLevel: 2)
        ) == 4
        expect(Self.definition(startingIndex: 1).continuesPreviousList) == false
        expect(Self.definition(startingIndex: 5).continuesPreviousList) == false
    }
}
