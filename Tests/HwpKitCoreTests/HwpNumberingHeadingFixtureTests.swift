@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개요 번호 정의 참조의 **실측 핀** (#152) — 최상위 개요 문단을 가진 픽스처는
    /// 헌법주석(`legacy-common-control-property`)과 한글.app으로 만든
    /// `outline-numbering`(개요 3 + 문단 번호 2) 둘이다.
    ///
    /// 조판 없이 문단을 걸어 참조를 푼다 (`HwpOutlineFixtureTests`와 같은 방식) —
    /// 조판을 거친 진단 건수는 `Tests/HwpKitTests/FixtureObjectRenderTests`가
    /// 같은 수(1,944)로 대조한다.
    final class HwpNumberingHeadingFixtureTests: XCTestCase {
        private func fixture(_ id: String) throws -> CoreHwp.HwpFile {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/\(id)/document.hwp")
            return try CoreHwp.HwpFile(fromPath: url.path)
        }

        /// 같은 문서의 HWPX 쌍 — `HwpFile`이 선두 바이트로 포맷을 가른다.
        private func hwpxFixture(_ id: String) throws -> CoreHwp.HwpFile {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/HwpxFixtures/\(id)/document.hwpx")
            return try CoreHwp.HwpFile(fromPath: url.path)
        }

        private struct Walk {
            var references: [HwpNumberingHeadingReference] = []
            /// 구역 인덱스 → 그 구역 정의의 참조 (1-based).
            var sectionReferenceIds: [UInt16] = []
        }

        /// 문단에 붙은 첫 구역 정의 — `HwpPaginator.sectionDef(in:)`과 같은 술어다.
        /// 헌법주석은 구역 1부터 단 정의가 앞서 첫 컨트롤이 구역 정의가 아니다.
        private func sectionDef(in paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpSectionDef? {
            for ctrl in paragraph.ctrlHeaderArray ?? [] {
                if case let .section(sectionDef) = ctrl {
                    return sectionDef
                }
            }
            return nil
        }

        private func walk(_ file: CoreHwp.HwpFile) -> Walk {
            let index = HwpIndex(from: file)
            var walk = Walk()
            for section in file.displaySectionArray {
                var sectionDef: CoreHwp.HwpSectionDef?
                for paragraph in section.paragraph {
                    if let found = self.sectionDef(in: paragraph) {
                        sectionDef = found
                        walk.sectionReferenceIds.append(found.numberParaShapeId)
                    }
                    let paraShapeId = UInt32(paragraph.paraHeader.paraShapeId)
                    guard let paraShape = index.paraShape(id: paraShapeId),
                          let reference = HwpNumberingHeadingReference.resolve(
                              paraShape: paraShape, sectionDef: sectionDef, index: index
                          )
                    else { continue }
                    walk.references.append(reference)
                }
            }
            return walk
        }

        /// 개요 문단 1,944개가 전부 구역 정의를 거쳐 정의에 닿는다 — 41개 구역이
        /// 41개 정의를 하나씩(순열로) 가리키고 문단 모양의 참조는 전부 0이다.
        func testLegacyOutlineParagraphsAllResolveThroughTheirSectionDefinitions() throws {
            let file = try fixture("legacy-common-control-property")
            let walk = walk(file)
            let outline = walk.references.filter { $0.kind == .outline }

            expect(outline.count) == 1944
            expect(walk.references.count) == outline.count
            expect(walk.sectionReferenceIds.count) == 41
            expect(Set(walk.sectionReferenceIds)) == Set(1 ... 41)
            expect(walk.sectionReferenceIds.first) == 1

            var resolvedDefinitions = Set<UInt32>()
            var levelCounts: [Int: Int] = [:]
            for reference in outline {
                guard case let .resolved(definitionIndex) = reference.definition else {
                    return fail("정의에 닿지 않은 개요 문단: \(reference)")
                }
                resolvedDefinitions.insert(definitionIndex)
                levelCounts[reference.level, default: 0] += 1
            }
            expect(resolvedDefinitions.count) == 41
            expect(levelCounts) == [1: 280, 2: 512, 3: 486, 4: 301, 5: 244, 6: 100, 7: 21]
            // 문단 모양 경로로는 한 건도 잡히지 않는다 — 종전 진단의 결함.
            let paraShapes = file.docInfo.idMappings.paraShapeArray
            let outlineShapesWithReference = paraShapes.filter {
                $0.property1Info.headingTypeRawValue == 1 && $0.numberingOrBulletId > 0
            }
            expect(outlineShapesWithReference).to(beEmpty())
        }

        /// 참조가 닿은 정의의 7수준 형식과 문단 머리 정보 — 41개 정의가 전부 같은
        /// 형식이고, 수준별 번호 종류는 로마 대문자·숫자·한글 가나다를 번갈아 쓴다.
        func testLegacyResolvedDefinitionsCarrySevenLevelFormats() throws {
            let file = try fixture("legacy-common-control-property")
            let index = HwpIndex(from: file)
            let walk = walk(file)
            let expectedFormats = ["^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"]

            var checked = 0
            for reference in walk.references {
                let numbering = try XCTUnwrap(reference.numbering(in: index))
                expect(numbering.formatArray.map(\.format)) == expectedFormats
                let format = try XCTUnwrap(reference.format(in: index))
                expect(format.format) == expectedFormats[reference.level - 1]
                expect(format.pattern.referencedLevels) == [reference.level]
                let info = try XCTUnwrap(format.paraHeadInfo)
                expect(info.numberFormat) == [2, 0, 8, 0, 8, 0, 8][reference.level - 1]
                expect(info.useInstWidth) == true
                expect(info.autoIndent) == true
                expect(info.textOffsetType) == HwpParaHeadTextOffsetType.percent
                expect(info.textOffset) == 50
                expect(info.charShapeId) == -1
                checked += 1
            }
            expect(checked) == 1944
        }

        /// `outline-numbering` — 개요 3개는 구역 정의(참조 2 → 사용자 정의 정의)를,
        /// 문단 번호 2개는 문단 모양(참조 1 → 한글 기본 정의)을 따른다. 두 종류가 서로
        /// 다른 정의에 닿는 유일한 실물이고 HWPX 쌍도 같은 결과여야 한다.
        func testOutlineNumberingFixtureResolvesBothHeadingKinds() throws {
            for file in [try fixture("outline-numbering"), try hwpxFixture("outline-numbering")] {
                let index = HwpIndex(from: file)
                let walk = walk(file)

                expect(walk.sectionReferenceIds) == [2]
                expect(walk.references.map(\.kind)) == [
                    .outline, .outline, .outline, .numbering, .numbering,
                ]
                expect(walk.references.map(\.level)) == [1, 2, 3, 1, 1]
                expect(walk.references.map(\.definition)) == [
                    .resolved(index: 1), .resolved(index: 1), .resolved(index: 1),
                    .resolved(index: 0), .resolved(index: 0),
                ]
                expect(walk.references.map { $0.format(in: index)?.format }) == [
                    "^1.", "^2.", "^3)", "^1.", "^1.",
                ]
                expect(walk.references.map(\.unsupportedHint)) == [
                    "개요 번호 문단 머리 (미렌더)", "개요 번호 문단 머리 (미렌더)",
                    "개요 번호 문단 머리 (미렌더)", "번호 매기기 문단 머리 (미렌더)",
                    "번호 매기기 문단 머리 (미렌더)",
                ]
            }
        }

        /// 개요 문단이 없는 문서에서는 참조가 없다 — 진단이 서지 않는 근거.
        func testFixturesWithoutHeadingsProduceNoReferences() throws {
            for id in ["noori", "multi-section", "plain-text-minimal"] {
                let walk = walk(try fixture(id))
                expect(walk.references).to(beEmpty(), description: id)
                // 구역 정의의 참조 자체는 실려 있다 (noori 2, multi-section 1·2).
                expect(walk.sectionReferenceIds.allSatisfy { $0 > 0 }).to(beTrue(), description: id)
            }
        }
    }
#endif
