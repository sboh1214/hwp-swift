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

    /// `oleObjects` 축이 **비어 있지 않게** 성립하는지 직접 핀한다 (#134).
    /// 등식만 두면 조인이 깨져 양쪽이 함께 nil이어도 통과한다 — chart 쌍은 두
    /// 포맷 모두 BinData에 닿는 OLE 개체 1건이고 차트 XML digest가 같아야 한다.
    func testChartPairProjectsResolvedOleChartOnBothFormats() throws {
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "chart").documentURL.path)
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "chart").documentURL.path
        )

        let hwpObjects = DocumentEquivalenceProjection.oleObjects(of: hwp)
        let hwpxObjects = DocumentEquivalenceProjection.oleObjects(of: hwpx)
        expect(hwpObjects.count) == 1
        expect(hwpxObjects.count) == 1
        expect(hwpObjects.first?.resolvesBinaryData) == true
        expect(hwpxObjects.first?.resolvesBinaryData) == true
        // 내장 차트가 실제로 디코드됐다 (nil이면 축이 공허해진다).
        expect(hwpObjects.first?.chartXMLDigest).toNot(beNil())
        expect(hwpxObjects.first?.chartXMLDigest) == hwpObjects.first?.chartXMLDigest
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

    /// 개체 앵커 오프셋 — 부호 있는 좌표라 두 포맷의 인코딩이 갈린다
    /// (HWPX는 UInt32 비트 패턴, 바이너리는 그대로 HWPUNIT). 이 축이 없어서
    /// noori의 표가 (-140, -140) → (0, 0)으로 밀린 회귀가 10쌍 등가 비교를
    /// 통과했다.
    struct AnchorOffset: Equatable {
        let vertical: Int32
        let horizontal: Int32
    }

    /// OLE 개체 요소 하나의 포맷 무관 투영 (#134).
    ///
    /// **BinItem id 숫자는 넣지 않는다** — id 공간은 재저장이 재생성하고(HWPX는
    /// manifest 등장 순서, `Hwpx/AGENTS.md`의 리맵 규약) 그래서 같은 개체가
    /// 포맷마다 다른 번호를 받을 수 있다. 이 투영이 id 매핑 인덱스를 제외하고
    /// 그림 축이 개수만 보는 것과 같은 이유다. 대신 참조가 실제로 닿는지와
    /// 내장 차트 XML을 비교한다.
    struct OleObject: Equatable {
        /// `binaryDataId`가 BinData 스트림에 닿는가 (댕글링이면 false).
        let resolvesBinaryData: Bool
        /// 내장 차트 XML의 digest — 차트가 아니거나 못 읽으면 nil.
        ///
        /// payload 전체는 축이 아니다: chart 쌍 실측에서 CFB의
        /// `OOXMLChartContents` 4,926바이트는 바이트 동일이지만 `Contents`
        /// 스트림이 1바이트 다르다. 그래서 렌더가 실제로 읽는 차트 XML만 본다.
        let chartXMLDigest: String?
    }

    /// 쪽 번호 위치(표 147) — HWPX `hp:pageNum`이 typed 승격돼야 HWP 쌍과
    /// 같은 컨트롤이 선다 (#135). 강등 상태면 HWPX 쪽 배열이 비어 등식이
    /// 깨진다. 4번째 WCHAR(`unused`)는 줄표 문자로 HWPX `sideChar`의 대응이다
    /// (#138). payload 바이트는 비교하지 않는다 — 바이너리는 뒤에 미해석
    /// UINT32가 붙은 20바이트 변형이 있어 포맷 무관 축이 아니다.
    struct PageNumberPosition: Equatable {
        let property: UInt32
        let userSymbol: UInt16
        let headDecoration: UInt16
        let tailDecoration: UInt16
        let sideChar: UInt16
    }

    let sectionCount: Int
    let sectionParagraphCounts: [Int]
    let sectionTexts: [String]
    let pageGeometries: [PageGeometry]
    let resolvedRunsByParagraph: [[ResolvedRun]]
    let tableShapes: [TableShape]
    let tableAnchorOffsets: [AnchorOffset]
    let imageCount: Int
    /// OLE 개체 요소의 **해석 결과** — HWPX `hp:ole`이 typed 승격돼야 HWP 쌍(gso +
    /// `$ole` 개체 요소)과 같은 개체 요소가 선다 (#134). 강등 상태면 HWPX 쪽
    /// 배열이 비어 등식이 깨진다. 컨트롤 종류(`.genShapeObject` ↔ `.ole`)는
    /// 포맷마다 다르므로 개체 요소 단위로 센다 — 그림 축과 같은 기준이다.
    let oleObjects: [OleObject]
    let pageNumberPositions: [PageNumberPosition]

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
        tableAnchorOffsets = FixtureDerivedValues.tables(from: file).map { table in
            AnchorOffset(
                vertical: Int32(bitPattern: table.commonCtrlProperty.verticalOffset),
                horizontal: Int32(bitPattern: table.commonCtrlProperty.horizontalOffset)
            )
        }
        imageCount = HwpxFixtureAssertions.imageBinItemIds(from: file).count
        oleObjects = Self.oleObjects(of: file)
        pageNumberPositions = FixtureDerivedValues.pageNumberPositions(from: file).map {
            PageNumberPosition(
                property: $0.property,
                userSymbol: $0.userSymbol,
                headDecoration: $0.headDecoration,
                tailDecoration: $0.tailDecoration,
                sideChar: $0.unused
            )
        }
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

    /// OLE 개체 요소를 문서 순서로 투영한다 — BinItem 조인은 `HwpImageStore`와
    /// 같은 규칙(binDataArray 등재 순서 + 1 → `streamId` → 스트림)이다.
    static func oleObjects(of file: HwpFile) -> [OleObject] {
        var streams: [UInt16: Data] = [:]
        for stream in file.binaryDataArray {
            guard let streamId = stream.streamId, streams[streamId] == nil else { continue }
            streams[streamId] = stream.data
        }
        var payloads: [UInt32: Data] = [:]
        for (index, entry) in file.docInfo.idMappings.binDataArray.enumerated() {
            guard let streamId = entry.streamId, let data = streams[streamId] else { continue }
            payloads[UInt32(index + 1)] = data
        }

        let elements = HwpxFixtureAssertions.shapeComponents(from: file).flatMap(\.oleArray)
        return elements.map { ole -> OleObject in
            let payload = ole.binaryDataId.flatMap { payloads[$0] }
            let chartXML = payload.flatMap { HwpEmbeddedChart.chartXML(fromOLEPayload: $0) }
            return OleObject(
                resolvesBinaryData: payload != nil,
                chartXMLDigest: chartXML.map(Self.digest)
            )
        }
    }

    /// FNV-1a 64비트 digest — 실패 메시지에 4,926자 차트 XML이 통째로 찍히지
    /// 않게 하면서 내용 변화는 잡는다 (CryptoKit은 Linux에 없다).
    static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
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
        expect(tableAnchorOffsets).to(
            equal(other.tableAnchorOffsets),
            description: "\(fixtureId) tableAnchorOffsets"
        )
        expect(imageCount).to(
            equal(other.imageCount), description: "\(fixtureId) imageCount"
        )
        expect(oleObjects).to(
            equal(other.oleObjects), description: "\(fixtureId) oleObjects"
        )
        expect(pageNumberPositions).to(
            equal(other.pageNumberPositions),
            description: "\(fixtureId) pageNumberPositions"
        )
    }
}
