@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 생성 (#153) — 합성 문서로 카운터 규칙(수준 승계·초기화·
    /// 시작 번호·정의 교체·구역 경계·종류별 분리·형식 조립)을 고정한다. 컨테이너
    /// 문단·조회·조판기 노출은 `HwpParagraphNumberingLookupTests`, 실물 핀은
    /// `HwpParagraphNumberingFixtureTests`다.
    final class HwpParagraphNumberingTests: XCTestCase {
        /// 수준별 번호 모양 로마 대문자·한글 가나다·숫자 — 헌법주석 1-3수준과 같다.
        private static let romanHangulDigit = [2, 8, 0, 8, 0, 8, 0]

        /// 문단 모양 id는 `HwpSynthetic.numberingIndex`의 사전을 따른다.
        private static func paragraph(_ text: String, shape: UInt16) throws -> HwpParagraph {
            try HwpSynthetic.styledParagraph(text, paraShapeId: shape)
        }

        private static func texts(_ numbering: HwpParagraphNumbering) -> [String] {
            numbering.entries.map(\.number.text)
        }

        private static func top(_ paragraphIndex: Int) -> HwpParagraphPath {
            HwpParagraphPath(sectionIndex: 0, paragraphIndex: paragraphIndex)
        }

        // MARK: - 수준

        /// 같은 수준은 1씩 늘고, 상위 수준이 늘면 하위 수준은 시작 번호로 돌아간다.
        /// 다수준 형식은 매겨지지 않은 상위 수준을 시작 번호로 보인다.
        func testLevelsIncrementAndDeeperLevelsResetWhenAnUpperLevelAdvances() throws {
            let definition = HwpSynthetic.numberingDefinition(
                formats: ["^1.", "^1.^2", "^1.^2.^3", "(^4)", "(^5)", "^6)", "^7)"]
            )
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("1", shape: 1), try Self.paragraph("1.1", shape: 2),
                    try Self.paragraph("1.1.1", shape: 3), try Self.paragraph("1.1.2", shape: 3),
                    try Self.paragraph("1.2", shape: 2), try Self.paragraph("1.2.1", shape: 3),
                    try Self.paragraph("2", shape: 1),
                    try Self.paragraph("2.1.1 (2수준 건너뜀)", shape: 3),
                    try Self.paragraph("2.1", shape: 2),
                ],
                numberings: [0: definition]
            )

            expect(Self.texts(numbering)) == [
                "1.", "1.1", "1.1.1", "1.1.2", "1.2", "1.2.1", "2.", "2.1.1", "2.1",
            ]
            expect(numbering.entries.map(\.number.numbers)) == [
                [1], [1, 1], [1, 1, 1], [1, 1, 2], [1, 2], [1, 2, 1], [2], [2, 1, 1], [2, 1],
            ]
            expect(numbering.entries.map(\.number.level)) == [1, 2, 3, 3, 2, 3, 1, 3, 2]
            expect(numbering.entries.allSatisfy { $0.number.kind == .outline }) == true
            expect(numbering.entries.allSatisfy { $0.number.definitionIndex == 0 }) == true
            // 위치 경로는 구역 첫 문단(구역 정의) 다음부터다.
            expect(numbering.paths) == (1 ... 9).map(Self.top)
        }

        /// 수준별 번호 모양 — 로마 대문자·한글 가나다·숫자 (헌법주석 1-3수준).
        func testEachLevelRendersWithItsOwnNumberShape() throws {
            let definition = HwpSynthetic.numberingDefinition(
                formats: ["^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"],
                numberFormats: Self.romanHangulDigit
            )
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("I", shape: 1), try Self.paragraph("가", shape: 2),
                    try Self.paragraph("1", shape: 3), try Self.paragraph("2", shape: 3),
                    try Self.paragraph("나", shape: 2), try Self.paragraph("II", shape: 1),
                    try Self.paragraph("(가)", shape: 4), try Self.paragraph("III", shape: 1),
                    try Self.paragraph("IV", shape: 1),
                ],
                numberings: [0: definition]
            )
            expect(Self.texts(numbering)) == [
                "I.", "가.", "1.", "2.", "나.", "II.", "(가)", "III.", "IV.",
            ]
        }

        // MARK: - 번호 매기기 목록

        /// 사이에 낀 본문·글머리표 문단은 목록을 끊지 않는다 ("앞 번호 목록에 이어").
        func testNumberingListContinuesAcrossBodyParagraphs() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("1", shape: 11), try Self.paragraph("2", shape: 11),
                    try Self.paragraph("본문", shape: 9), try Self.paragraph("글머리표", shape: 8),
                    try Self.paragraph("3", shape: 11), try Self.paragraph("가", shape: 12),
                    try Self.paragraph("4", shape: 11),
                ],
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            expect(Self.texts(numbering)) == ["1.", "2.", "3.", "1.", "4."]
            expect(numbering.paths) == [1, 2, 5, 6, 7].map(Self.top)
            expect(numbering.entries.allSatisfy { $0.number.kind == .numbering }) == true
            expect(numbering.number(at: Self.top(3))).to(beNil())
            expect(numbering.number(at: Self.top(4))).to(beNil())
        }

        /// 정의가 바뀌는 번호 문단에서 새 정의의 시작 번호 방식을 본다 — 새 번호면
        /// 그 정의의 시작 번호부터, 이어 매기기면 앞 목록을 잇는다.
        func testSwitchingDefinitionsRestartsOrContinuesByTheNewDefinitionsStartMode() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("A1", shape: 11), try Self.paragraph("A2", shape: 11),
                    try Self.paragraph("B5", shape: 21), try Self.paragraph("B6", shape: 21),
                    try Self.paragraph("C7 이어", shape: 31), try Self.paragraph("C8", shape: 31),
                    try Self.paragraph("A1 다시", shape: 11), try Self.paragraph("C2 이어", shape: 31),
                ],
                numberings: [
                    0: HwpSynthetic.numberingDefinition(startingIndex: 1),
                    1: HwpSynthetic.numberingDefinition(startingIndex: 5),
                    2: HwpSynthetic.numberingDefinition(
                        formats: ["(^1)", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"],
                        startingIndex: 0
                    ),
                ]
            )
            expect(Self.texts(numbering)) == ["1.", "2.", "5.", "6.", "(7)", "(8)", "1.", "(2)"]
            expect(numbering.entries.map(\.number.definitionIndex)) == [0, 0, 1, 1, 2, 2, 0, 2]
        }

        /// 수준별 시작 번호 — 새 번호로 시작하는 정의의 각 수준이 그 값에서 출발하고,
        /// 상위 수준이 늘어 되돌아갈 때도 그 값이다.
        func testPerLevelStartingNumbersApplyOnRestartAndReset() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("5", shape: 11), try Self.paragraph("3", shape: 12),
                    try Self.paragraph("4", shape: 12), try Self.paragraph("6", shape: 11),
                    try Self.paragraph("3 다시", shape: 12),
                ],
                numberings: [0: HwpSynthetic.numberingDefinition(
                    startingIndex: 1, startingIndexArray: [5, 3, 1, 1, 1, 1, 1]
                )]
            )
            expect(Self.texts(numbering)) == ["5.", "3.", "4.", "6.", "3."]
            expect(numbering.entries.map(\.number.numbers)) == [[5], [5, 3], [5, 4], [6], [6, 3]]
        }

        // MARK: - 구역 경계

        /// 개요는 구역 시작에서 구역 정의의 정의를 본다 — 새 번호면 다시 세고, 이어
        /// 매기기면 앞 구역의 번호를 잇는다. 정의가 같아도 같다.
        func testOutlineRestartsOrContinuesAtSectionStartByTheSectionDefinition() throws {
            func section(outlineNumberingId: UInt16, titles: [String]) throws -> HwpSection {
                HwpSynthetic.numberingSection(
                    outlineNumberingId: outlineNumberingId,
                    paragraphs: try titles.map { try Self.paragraph($0, shape: 1) }
                )
            }
            let restart = HwpSynthetic.numberingDefinition(startingIndex: 1)
            let continued = HwpSynthetic.numberingDefinition(
                formats: ["^1)", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"], startingIndex: 0
            )
            let numbering = HwpParagraphNumbering.generate(
                sections: [
                    try section(outlineNumberingId: 1, titles: ["1", "2"]),
                    try section(outlineNumberingId: 1, titles: ["1 (같은 정의, 새 번호)"]),
                    try section(outlineNumberingId: 2, titles: ["2) 이어", "3) 이어"]),
                    try section(outlineNumberingId: 1, titles: ["1 새 번호"]),
                ],
                index: HwpSynthetic.numberingIndex(numberings: [0: restart, 1: continued])
            )
            expect(Self.texts(numbering)) == ["1.", "2.", "1.", "2)", "3)", "1."]
            expect(numbering.paths.map(\.paragraph.sectionIndex)) == [0, 0, 1, 2, 2, 3]
        }

        /// 첫 구역의 정의가 이어 매기기여도 앞이 없으니 시작 번호부터다 (헌법주석 첫
        /// 구역의 정의 1이 그렇다).
        func testFirstSectionWithContinuationDefinitionStartsAtTheStartingNumber() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("1", shape: 1), try Self.paragraph("2", shape: 1)],
                numberings: [0: HwpSynthetic.numberingDefinition(startingIndex: 0)]
            )
            expect(Self.texts(numbering)) == ["1.", "2."]
        }

        // MARK: - 종류 분리

        /// 개요와 번호 매기기는 같은 정의를 가리켜도 카운터를 나누지 않는다 — 각자 센다.
        func testOutlineAndNumberingCountSeparatelyOnASharedDefinition() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("개요 1", shape: 1), try Self.paragraph("번호 1", shape: 11),
                    try Self.paragraph("번호 2", shape: 11), try Self.paragraph("개요 2", shape: 1),
                    try Self.paragraph("개요 2.가", shape: 2), try Self.paragraph("번호 3", shape: 11),
                    try Self.paragraph("번호 3.가", shape: 12),
                ],
                numberings: [0: HwpSynthetic.numberingDefinition(
                    formats: ["^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"],
                    numberFormats: Self.romanHangulDigit
                )]
            )
            expect(Self.texts(numbering)) == ["I.", "I.", "II.", "II.", "가.", "III.", "가."]
            expect(numbering.entries.map(\.number.kind)) == [
                .outline, .numbering, .numbering, .outline, .outline, .numbering, .numbering,
            ]
        }

        // MARK: - 참조 없음·댕글링·형식 없음

        /// 정의에 닿지 않는 문단은 번호도 없고 카운터도 늘리지 않는다.
        func testUnresolvedReferencesAreSkippedWithoutConsumingANumber() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("1", shape: 11), try Self.paragraph("댕글링", shape: 31),
                    try Self.paragraph("2", shape: 11), try Self.paragraph("개요 참조 없음", shape: 1),
                ],
                numberings: [0: HwpSynthetic.numberingDefinition()],
                outlineNumberingId: 0
            )
            expect(Self.texts(numbering)) == ["1.", "2."]
            expect(numbering.paths) == [1, 3].map(Self.top)
        }

        /// 형식 슬롯이 비어 있으면 라벨은 빈 문자열이되 번호는 센다 — 확장 수준(8)이
        /// 없는 5.0 저장본의 8수준 문단이 그렇다.
        func testMissingOrEmptyFormatSlotsCountButRenderNothing() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("8수준 (빈 형식)", shape: 18),
                    try Self.paragraph("8수준 둘째", shape: 18),
                    try Self.paragraph("1", shape: 11),
                    try Self.paragraph("8수준 셋째 (1수준이 비웠다)", shape: 18),
                ],
                numberings: [0: HwpSynthetic.numberingDefinition(extendedFormats: ["", "^9", "^n"])]
            )
            expect(Self.texts(numbering)) == ["", "", "1.", ""]
            expect(numbering.entries.map(\.number.level)) == [8, 8, 1, 8]
            expect(numbering.entries.map(\.number.number)) == [1, 2, 1, 1]

            let withoutExtended = HwpSynthetic.generateNumbering(
                [try Self.paragraph("8수준 (확장 배열 없음)", shape: 18)],
                numberings: [0: HwpSynthetic.numberingDefinition()]
            )
            expect(Self.texts(withoutExtended)) == [""]
            expect(withoutExtended.entries.map(\.number.numbers)) == [[1, 1, 1, 1, 1, 1, 1, 1]]
        }

        // MARK: - 레벨 경로·확장 수준

        /// `^n`은 1수준부터 그 수준까지를 각 수준의 번호 모양으로 `.`로 잇고 `^N`은
        /// 마침표를 하나 더 찍는다. 문단 수준보다 깊은 참조는 그 수준의 시작 번호다.
        func testLevelPathAndDeeperReferencesRenderFromStartingNumbers() throws {
            let definition = HwpSynthetic.numberingDefinition(
                formats: ["^1.", "^n", "^N)", "^n ^9", "(^5)", "^6)", "^7)"],
                numberFormats: Self.romanHangulDigit,
                startingIndexArray: [1, 1, 1, 1, 1, 1, 1],
                extendedFormats: ["^8", "^9", "^9.^10)"],
                extendedNumberFormats: [1, 10, 3],
                extendedStartingIndexArray: [1, 4, 1]
            )
            let numbering = HwpSynthetic.generateNumbering(
                [
                    try Self.paragraph("I", shape: 1), try Self.paragraph("I.가", shape: 2),
                    try Self.paragraph("I.가.1.", shape: 3), try Self.paragraph("I.가.2.", shape: 3),
                    try Self.paragraph("I.가.2.가 ㄹ", shape: 4), try Self.paragraph("II", shape: 1),
                    try Self.paragraph("II.가", shape: 2),
                ],
                numberings: [0: definition]
            )
            expect(Self.texts(numbering)) == [
                "I.", "I.가", "I.가.1.)", "I.가.2.)", "I.가.2.가 ㄹ", "II.", "II.가",
            ]
        }

        /// 확장 수준 8은 저장 비트가 담는 마지막 수준이다 — 확장 형식·확장 시작 번호를 쓴다.
        func testExtendedLevelEightUsesExtendedFormatsAndStarts() throws {
            let numbering = HwpSynthetic.generateNumbering(
                [try Self.paragraph("③", shape: 18), try Self.paragraph("④", shape: 18)],
                numberings: [0: HwpSynthetic.numberingDefinition(
                    extendedFormats: ["^8", "", ""],
                    extendedNumberFormats: [1, 0, 0],
                    extendedStartingIndexArray: [3, 1, 1]
                )]
            )
            expect(Self.texts(numbering)) == ["③", "④"]
            expect(numbering.entries.map(\.number.level)) == [8, 8]
        }
    }
#endif
