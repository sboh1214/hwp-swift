@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 같은 문서의 HWP↔HWPX 파싱 등가 — 이 지원의 핵심 회귀 축.
///
/// 완전 모델 등가는 성립하지 않는다: 한글.app 재저장이 id 공간·lineseg·
/// 미리보기·요약을 재생성하기 때문이다. 그래서 **포맷 무관 투영**만 비교한다.
/// 투영에서 명시적으로 제외한 것: rawPayload 계열·lineseg(재조판 캐시)·
/// id 매핑 인덱스(리맵됨 — 해석 결과로만 비교)·fileHeader·summary·preview·
/// viewSectionArray·컨트롤 레코드 순서·numbering/bullet(1차 범위 밖).
final class HwpxHwpEquivalenceTests: XCTestCase {
    /// P1(2× 스케일)·P2-7(pageBreak 의미)의 실물 잠금 — noori 쌍의 문단 모양
    /// 수치와 표 나눔 비트가 문서 순서 위치별로 일치해야 한다.
    func testNooriParaShapeDimensionsAndTableBreaksMatchHwpSource() throws {
        let hwp = try HwpFile(
            fromPath: FixtureLoader.load(id: "noori").documentURL.path
        )
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "noori").documentURL.path
        )

        func dimensions(_ file: HwpFile) -> [[Int32]] {
            file.docInfo.idMappings.paraShapeArray.map {
                [
                    $0.marginLeft, $0.marginRight, $0.indent,
                    $0.paragraphSpacingTop, $0.paragraphSpacingBottom,
                    $0.resolvedLineSpacingValue,
                ]
            }
        }
        expect(dimensions(hwpx)) == dimensions(hwp)

        func pageBreakBits(_ file: HwpFile) -> [Int] {
            FixtureDerivedValues.tables(from: file).map {
                Int($0.tableProperty.property & 0b11)
            }
        }
        expect(pageBreakBits(hwpx)) == pageBreakBits(hwp)
    }

    func testConvertedFixturesProjectEquallyToTheirHwpSources() throws {
        var comparedCount = 0
        for fixture in try HwpxFixtureLoader.loadAll() {
            guard let sourceId = fixture.manifest.sourceHwpFixture,
                  fixture.manifest.expectedError == nil
            else {
                continue
            }
            let source = try FixtureLoader.load(id: sourceId)
            let hwp = try HwpFile(fromPath: source.documentURL.path)
            let hwpx = try HwpFile(fromPath: fixture.documentURL.path)

            let hwpProjection = DocumentEquivalenceProjection(of: hwp)
            let hwpxProjection = DocumentEquivalenceProjection(of: hwpx)
            hwpProjection.assertEqual(
                to: hwpxProjection, fixtureId: fixture.manifest.id
            )
            comparedCount += 1
        }
        expect(comparedCount) >= 10
    }
}

/// 포맷 무관 문서 투영 — `HwpFile`만으로 만든다.
struct DocumentEquivalenceProjection {
    /// 밑줄 종류는 비교하지 않는다 — HWP5 바이너리는 취소선 견본의 밑줄
    /// 종류 비트가 2로 읽히는 반면(리포 해석은 `.above`) 한글.app의 HWPX
    /// 저장본은 같은 모양을 `strikeout`으로 적는다 (CharShape 픽스처 실측).
    /// 교차 포맷 표현이 갈리는 필드라 실파일 검증 항목으로 남긴다
    /// (`Sources/CoreHwp/Hwpx/AGENTS.md`).
    struct ResolvedRun: Equatable {
        let baseSize: Int32
        let isBold: Bool
        let isItalic: Bool
        let faceColor: HwpColor
    }

    struct PageGeometry: Equatable {
        let width: UInt32
        let height: UInt32
        let margins: [UInt32]
    }

    struct TableShape: Equatable {
        let cellCount: Int
        let spans: [[UInt16]]
    }

    let sectionCount: Int
    let sectionParagraphCounts: [Int]
    let sectionTexts: [String]
    let pageGeometries: [PageGeometry]
    let resolvedRunsByParagraph: [[ResolvedRun]]
    let tableShapes: [TableShape]
    let imageCount: Int

    init(of file: HwpFile) {
        sectionCount = file.sectionArray.count
        sectionParagraphCounts = file.sectionArray.map(\.paragraph.count)
        sectionTexts = file.sectionArray.map(Self.printableText(of:))
        pageGeometries = file.sectionArray.compactMap { section in
            guard case let .section(sectionDef)? =
                section.paragraph.first?.ctrlHeaderArray?.first
            else {
                return nil
            }
            let pageDef = sectionDef.pageDef
            return PageGeometry(
                width: pageDef.width,
                height: pageDef.height,
                margins: [
                    pageDef.marginLeft, pageDef.marginRight,
                    pageDef.marginTop, pageDef.marginBottom,
                ]
            )
        }
        resolvedRunsByParagraph = Self.resolvedRuns(of: file)
        tableShapes = FixtureDerivedValues.tables(from: file).map { table in
            TableShape(
                cellCount: table.cellArray.count,
                spans: table.cellArray.map { cell in
                    guard let property = cell.header.cellProperty else {
                        return [1, 1]
                    }
                    return [property.columnSpan, property.rowSpan]
                }
            )
        }
        imageCount = HwpxFixtureAssertions.imageBinItemIds(from: file).count
    }

    /// 인쇄 가능한 문자만 문서 순서(표 셀 재귀 포함)로 모은다 — 제어 문자
    /// (문단 끝 13 등)는 셀 내부 문단 분할 차이에 흔들려 비교 축이 아니다.
    static func printableText(of section: HwpSection) -> String {
        func walk(_ paragraphs: [HwpParagraph]) -> String {
            paragraphs.map { paragraph -> String in
                var out = ""
                for char in paragraph.paraText?.charArray ?? []
                    where char.type == .char && char.value >= 32
                {
                    out += String(decoding: [char.value], as: UTF16.self)
                }
                for ctrl in paragraph.ctrlHeaderArray ?? [] {
                    if case let .table(table) = ctrl {
                        out += table.cellArray.map { walk($0.paragraphArray) }.joined()
                    }
                }
                return out
            }.joined()
        }
        return walk(section.paragraph)
    }

    /// 문단별 글자 모양 run — id가 아니라 **해석된 속성**의 인접 dedupe
    /// 수열이다. 재저장이 id를 재배열하고 동일 속성의 charPr을 합치거나
    /// 갈라도 시각 변화 지점의 수열은 같아야 한다.
    static func resolvedRuns(of file: HwpFile) -> [[ResolvedRun]] {
        let charShapes = file.docInfo.idMappings.charShapeArray
        return file.sectionArray.flatMap(\.paragraph).map { paragraph in
            var runs: [ResolvedRun] = []
            for shapeId in paragraph.paraCharShape.shapeId {
                guard let shape = charShapes.indices.contains(Int(shapeId))
                    ? charShapes[Int(shapeId)] : nil
                else {
                    continue
                }
                let run = ResolvedRun(
                    baseSize: shape.baseSize,
                    isBold: shape.property.isBold,
                    isItalic: shape.property.isItalic,
                    faceColor: shape.faceColor
                )
                if runs.last != run {
                    runs.append(run)
                }
            }
            return runs
        }
    }

    func assertEqual(to other: DocumentEquivalenceProjection, fixtureId: String) {
        expect(sectionCount).to(
            equal(other.sectionCount), description: "\(fixtureId) sectionCount"
        )
        expect(sectionParagraphCounts).to(
            equal(other.sectionParagraphCounts),
            description: "\(fixtureId) sectionParagraphCounts"
        )
        expect(sectionTexts).to(
            equal(other.sectionTexts), description: "\(fixtureId) sectionTexts"
        )
        expect(pageGeometries).to(
            equal(other.pageGeometries), description: "\(fixtureId) pageGeometries"
        )
        expect(resolvedRunsByParagraph).to(
            equal(other.resolvedRunsByParagraph),
            description: "\(fixtureId) resolvedRunsByParagraph"
        )
        expect(tableShapes).to(
            equal(other.tableShapes), description: "\(fixtureId) tableShapes"
        )
        expect(imageCount).to(
            equal(other.imageCount), description: "\(fixtureId) imageCount"
        )
    }
}
