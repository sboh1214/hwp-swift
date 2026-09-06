@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개요·번호 매기기 문단 머리의 번호 정의 참조 해석과 그 미지원 진단 (#152) —
    /// 합성 문서로 정상·생략(참조 0)·잘못된 참조 세 경로를 고정한다. 실측 핀은
    /// `HwpNumberingHeadingFixtureTests`(헌법주석)가 잡는다.
    final class HwpNumberingHeadingReferenceTests: XCTestCase {
        private typealias Reference = HwpNumberingHeadingReference

        private var definition: CoreHwp.HwpNumbering {
            HwpSynthetic.numberingDefinition()
        }

        // MARK: - 참조 해석 (순수 함수)

        /// 개요(종류 1)는 문단 모양이 아니라 구역 정의의 참조를 쓴다 — 문단 모양의
        /// `numberingOrBulletId`가 0이어도 정의에 닿는다.
        func testOutlineHeadingResolvesThroughTheSectionDefinition() throws {
            let index = HwpSynthetic.outlineIndex(numberings: [1: definition])
            let reference = try XCTUnwrap(Reference.resolve(
                paraShape: HwpSynthetic.outlineParaShape(levelRawValue: 2, numberingOrBulletId: 0),
                sectionDef: HwpSynthetic.sectionDef(outlineNumberingId: 2),
                index: index
            ))

            expect(reference.kind) == Reference.Kind.outline
            expect(reference.level) == 3
            expect(reference.definition) == Reference.Definition.resolved(index: 1)
            expect(reference.numbering(in: index)?.formatArray.map(\.format)) == [
                "^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)",
            ]
            expect(reference.format(in: index)?.format) == "^3."
            expect(reference.unsupportedHint) == "개요 번호 문단 머리 (미렌더)"
        }

        /// 문단 모양의 참조는 개요에 영향을 주지 않는다 — 구역 정의만이 출처다.
        func testOutlineHeadingIgnoresTheParagraphShapeReference() {
            let index = HwpSynthetic.outlineIndex(numberings: [0: definition])
            let reference = Reference.resolve(
                paraShape: HwpSynthetic.outlineParaShape(levelRawValue: 0, numberingOrBulletId: 7),
                sectionDef: HwpSynthetic.sectionDef(outlineNumberingId: 1),
                index: index
            )
            expect(reference?.definition) == Reference.Definition.resolved(index: 0)
        }

        /// 참조 0과 구역 정의 부재는 "정의 없음"이다 — 빈 문서 기본값을 지어내지 않는다.
        func testZeroOrMissingSectionReferenceIsNone() {
            let index = HwpSynthetic.outlineIndex(numberings: [0: definition])
            let shape = HwpSynthetic.outlineParaShape(levelRawValue: 0)

            let zero = Reference.resolve(
                paraShape: shape,
                sectionDef: HwpSynthetic.sectionDef(outlineNumberingId: 0),
                index: index
            )
            expect(zero?.definition) == Reference.Definition.none
            expect(zero?.unsupportedHint) == "개요 번호 문단 머리 (번호 정의 참조 없음)"

            let missing = Reference.resolve(paraShape: shape, sectionDef: nil, index: index)
            expect(missing?.definition) == Reference.Definition.none
        }

        /// 정의 배열 밖 참조는 댕글링이다 — id를 진단에 남긴다.
        func testReferenceOutsideTheDefinitionsIsDangling() {
            let index = HwpSynthetic.outlineIndex(numberings: [0: definition])
            let reference = Reference.resolve(
                paraShape: HwpSynthetic.outlineParaShape(levelRawValue: 0),
                sectionDef: HwpSynthetic.sectionDef(outlineNumberingId: 3),
                index: index
            )
            expect(reference?.definition) == Reference.Definition.dangling(id: 3)
            expect(reference?.unsupportedHint) == "개요 번호 문단 머리 (없는 번호 정의 3 참조)"
            expect(reference?.numbering(in: index)).to(beNil())
            expect(reference?.format(in: index)).to(beNil())
        }

        /// 번호 매기기(종류 2)는 문단 모양의 참조를 쓴다 — 구역 정의는 보지 않는다.
        func testNumberingHeadingResolvesThroughTheParagraphShape() {
            let index = HwpSynthetic.outlineIndex(numberings: [1: definition])
            let sectionDef = HwpSynthetic.sectionDef(outlineNumberingId: 9)

            let resolved = Reference.resolve(
                paraShape: HwpSynthetic.numberingParaShape(
                    levelRawValue: 4, numberingOrBulletId: 2
                ),
                sectionDef: sectionDef, index: index
            )
            expect(resolved?.kind) == Reference.Kind.numbering
            expect(resolved?.level) == 5
            expect(resolved?.definition) == Reference.Definition.resolved(index: 1)
            expect(resolved?.unsupportedHint) == "번호 매기기 문단 머리 (미렌더)"

            let none = Reference.resolve(
                paraShape: HwpSynthetic.numberingParaShape(
                    levelRawValue: 0, numberingOrBulletId: 0
                ),
                sectionDef: sectionDef, index: index
            )
            expect(none?.definition) == Reference.Definition.none
            expect(none?.unsupportedHint) == "번호 매기기 문단 머리 (번호 정의 참조 없음)"

            let dangling = Reference.resolve(
                paraShape: HwpSynthetic.numberingParaShape(
                    levelRawValue: 0, numberingOrBulletId: 5
                ),
                sectionDef: sectionDef, index: index
            )
            expect(dangling?.definition) == Reference.Definition.dangling(id: 5)
            expect(dangling?.unsupportedHint) == "번호 매기기 문단 머리 (없는 번호 정의 5 참조)"
        }

        /// 글머리표(종류 3)와 머리 없는 문단은 대상이 아니다.
        func testBulletAndPlainParagraphsAreNotReferences() {
            let index = HwpSynthetic.outlineIndex(numberings: [0: definition])
            let bullet = CoreHwp.HwpParaShape(
                property1: 3 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 1
            )
            expect(Reference.resolve(
                paraShape: bullet, sectionDef: HwpSynthetic.sectionDef(), index: index
            )).to(beNil())
            expect(Reference.resolve(
                paraShape: HwpSynthetic.plainParaShape(), sectionDef: HwpSynthetic.sectionDef(),
                index: index
            )).to(beNil())
        }

        // MARK: - 조판 진단

        /// 정의에 닿은 개요 문단은 라벨을 그리므로(#154) 진단이 없다 — 종전의
        /// "(미렌더)" 한 건은 라벨 전치로 바뀌었고 탐색 목록은 그대로다.
        func testEachOutlineParagraphRendersItsLabelInsteadOfADiagnostic() async throws {
            let shapes = Dictionary(uniqueKeysWithValues: (UInt32(0) ... 2).map { level in
                (level + 1, HwpSynthetic.outlineParaShape(levelRawValue: level))
            })
            let bodyParagraphs = try (UInt32(0) ... 2).map { level in
                try HwpSynthetic.styledParagraph("제목 \(level)", paraShapeId: UInt16(level) + 1)
            } + [try HwpSynthetic.styledParagraph("본문", paraShapeId: 9)]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: bodyParagraphs,
                index: HwpSynthetic.outlineIndex(
                    paraShapes: shapes.merging(
                        [9: HwpSynthetic.plainParaShape()]
                    ) { first, _ in first },
                    numberings: [0: definition]
                )
            )

            _ = await paginator.totalPages()
            let unsupported = await paginator.unsupportedElements()
            let outline = await paginator.outline()

            expect(unsupported.map(\.hint)).to(beEmpty())
            expect(outline.count) == 3
            // 라벨 = 정의 형식(`^1.`·`^2.`·`^3.`)에 수준별 첫 번호 — 본문 문단은 없다.
            let texts = try await Self.blockTexts(of: paginator)
            expect(texts) == ["1. 제목 0", "1. 제목 1", "1. 제목 2", "본문"]
        }

        /// 첫 쪽 블록의 조판 문자열 — 라벨 전치를 본문 문단과 함께 본다.
        static func blockTexts(of paginator: HwpPaginator) async throws -> [String] {
            let page = try await paginator.page(at: 0)
            // 구역 정의 문단(컨트롤 마커뿐)은 뺀다.
            return (page?.blocks.compactMap { $0.attributedString?.string } ?? [])
                .filter { $0.contains { $0 != "\u{FFFC}" } }
        }

        /// 구역 정의의 참조가 0이면 "참조 없음", 정의 밖이면 댕글링으로 보고한다.
        func testSectionReferenceGapsAreReportedDistinctly() async throws {
            for (outlineNumberingId, hint) in [
                (UInt16(0), "개요 번호 문단 머리 (번호 정의 참조 없음)"),
                (UInt16(7), "개요 번호 문단 머리 (없는 번호 정의 7 참조)"),
            ] {
                let paginator = HwpSynthetic.outlinePaginator(
                    bodyParagraphs: [try HwpSynthetic.styledParagraph("제목", paraShapeId: 1)],
                    index: HwpSynthetic.outlineIndex(
                        paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)],
                        numberings: [0: definition]
                    ),
                    outlineNumberingId: outlineNumberingId
                )
                _ = await paginator.totalPages()
                let hints = await paginator.unsupportedElements().map(\.hint)
                expect(hints).to(equal([hint]), description: "참조 \(outlineNumberingId)")
            }
        }

        /// 번호 매기기 문단은 문단 모양의 참조를 따른다 — 정의에 닿으면 라벨을
        /// 그리고(#154), 참조 0은 조용히 지나가지 않고 진단으로 남는다.
        func testNumberingParagraphsReportTheirOwnReference() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph("번호 1", paraShapeId: 1),
                    try HwpSynthetic.styledParagraph("번호 0", paraShapeId: 2),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [
                        1: HwpSynthetic.numberingParaShape(
                            levelRawValue: 0, numberingOrBulletId: 1
                        ),
                        2: HwpSynthetic.numberingParaShape(
                            levelRawValue: 0, numberingOrBulletId: 0
                        ),
                    ],
                    numberings: [0: definition]
                ),
                // 구역 정의의 참조는 번호 매기기에 쓰이지 않는다.
                outlineNumberingId: 0
            )

            _ = await paginator.totalPages()
            let hints = await paginator.unsupportedElements().map(\.hint)
            expect(hints) == ["번호 매기기 문단 머리 (번호 정의 참조 없음)"]
            let texts = try await Self.blockTexts(of: paginator)
            expect(texts) == ["1. 번호 1", "번호 0"]
        }

        /// 구역마다 참조가 다르면 각 구역의 문단이 자기 구역의 정의를 본다 —
        /// 구역 첫 문단도 포함해서 (`applySectionDef`가 진단보다 앞선다).
        func testEachSectionResolvesAgainstItsOwnDefinition() async throws {
            let index = HwpSynthetic.outlineIndex(
                paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)],
                numberings: [0: definition, 1: definition]
            )
            func section(outlineNumberingId: UInt16, title: String) throws -> CoreHwp.HwpSection {
                var section = HwpSynthetic.section(
                    firstParagraphControls: [
                        .section(HwpSynthetic.sectionDef(outlineNumberingId: outlineNumberingId)),
                    ],
                    bodyParagraphs: [try HwpSynthetic.styledParagraph(title, paraShapeId: 1)]
                )
                // 구역 첫 문단 자체도 개요로 만들어 순서 의존을 함께 본다.
                section.paragraph[0].paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: 1, paraStyleId: 0
                )
                return section
            }
            let paginator = HwpPaginator(
                sections: [
                    try section(outlineNumberingId: 2, title: "둘째 정의"),
                    try section(outlineNumberingId: 9, title: "댕글링"),
                ],
                index: index,
                fontResolver: .testDeterministic
            )

            _ = await paginator.totalPages()
            let hints = await paginator.unsupportedElements().map(\.hint)
            // 첫 구역의 두 문단은 둘째 정의로 라벨을 그리고(#154), 댕글링 구역만 남는다.
            expect(hints) == [
                "개요 번호 문단 머리 (없는 번호 정의 9 참조)",
                "개요 번호 문단 머리 (없는 번호 정의 9 참조)",
            ]
            let texts = try await Self.blockTexts(of: paginator)
            expect(texts.filter { $0.hasPrefix("1. ") || $0.hasPrefix("2. ") }.count) == 2
        }
    }
#endif
