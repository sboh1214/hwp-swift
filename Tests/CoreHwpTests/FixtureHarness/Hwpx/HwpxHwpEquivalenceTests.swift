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
/// viewSectionArray·컨트롤 레코드 순서.
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

    /// 번호·글머리표 축이 **비어 있지 않게** 성립하는지 직접 핀한다 (#133).
    /// 등식만 두면 두 포맷이 함께 비어도 통과한다 — noori 쌍은 번호 정의 2종·
    /// 글머리표 1종이고, 글머리표 문단 머리를 쓰는 문단이 표 셀 안에 2개다.
    func testNooriPairProjectsNumberingAndBulletDefinitionsOnBothFormats() throws {
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "noori").documentURL.path)
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "noori").documentURL.path
        )
        let hwpProjection = DocumentEquivalenceProjection(of: hwp)
        let hwpxProjection = DocumentEquivalenceProjection(of: hwpx)

        expect(hwpProjection.numberingDefinitions.count) == 2
        expect(hwpxProjection.numberingDefinitions.count) == 2
        expect(hwpProjection.bulletDefinitions.count) == 1
        expect(hwpxProjection.bulletDefinitions.count) == 1
        expect(hwpxProjection.bulletDefinitions.first?.char) == "-"
        expect(hwpxProjection.numberingDefinitions.first?.formats.first) == "^1."
        // 글머리표 문단 머리(종류 3)를 쓰는 문단은 표 셀 안 2개다.
        let bulletHeadings = hwpxProjection.paragraphHeadings.filter { $0.kind == 3 }
        expect(bulletHeadings.count) == 2
        expect(bulletHeadings.allSatisfy { $0.definitionId == 1 }) == true
        expect(hwpProjection.paragraphHeadings.filter { $0.kind == 3 }) == bulletHeadings
        // 구역 정의의 개요 번호 참조 — noori는 두 번째 정의(id "2" → 1-based 2)를
        // 가리키고, HWP 쌍의 `numberParaShapeId`도 2다 (#152).
        expect(hwpProjection.sectionOutlineNumberingIds) == [2]
        expect(hwpxProjection.sectionOutlineNumberingIds) == [2]
    }

    /// 구역별 개요 번호 참조 축이 **구역마다** 성립하는지 직접 핀한다 (#152) —
    /// multi-section 쌍은 두 구역이 서로 다른 정의(1·2)를 가리킨다. HWPX id를
    /// 숫자 그대로 실으면 여기서는 우연히 맞으므로, 조작 대조는
    /// `HwpxSecPrOutlineReferenceTests`가 dense하지 않은 id로 한다.
    func testMultiSectionPairProjectsPerSectionOutlineNumberingIds() throws {
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "multi-section").documentURL.path)
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "multi-section").documentURL.path
        )

        expect(DocumentEquivalenceProjection(of: hwp).sectionOutlineNumberingIds) == [1, 2]
        expect(DocumentEquivalenceProjection(of: hwpx).sectionOutlineNumberingIds) == [1, 2]
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
        expect(comparedCount) >= 11
    }
}

/// 포맷 무관 문서 투영 — `HwpFile`만으로 만든다.
struct DocumentEquivalenceProjection {
    /// 밑줄 종류는 스펙 미정의 값 2(`undefined2`)만 없음으로 접어 비교한다 —
    /// 취소선 견본(CharShape·CharShapeProperty [18])이 HWP5에서는 그 값을 취소선
    /// 비트와 함께 갖는데 한글.app의 HWPX 저장본은 밑줄 없음 + `strikeout`으로
    /// 적기 때문이다 (#136). 나머지 값(없음·글자 아래·글자 위 = 3)은 두 포맷이
    /// 같은 케이스로 모여야 한다 (#149 — `underline-above` 쌍).
    struct ResolvedRun: Equatable {
        let baseSize: Int32
        let isBold: Bool
        let isItalic: Bool
        let faceColor: HwpColor
        let underlineType: HwpUnderlineType
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
    /// noori의 표가 (-140, -140) → (0, 0)으로 밀린 회귀가 11쌍 등가 비교를
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

    /// 문단 번호 정의 하나 (#133).
    ///
    /// **확장 수준(8-10)은 축이 아니다** — 표 38의 확장 필드는 5.1.0.0 이상에만
    /// 있고 noori HWP 쌍은 5.0.3.4라 배열 자체가 없다. HWPX 재저장본은 항상
    /// 5.1.1.0이므로 수준 개수를 직접 비교하면 유효한 쌍이 깨진다 (`oleObjects`가
    /// 재부여되는 BinItem id를 뺀 것과 같은 판단). 두 포맷이 공통으로 갖는
    /// 수준 1-7의 형식 문자열·수준별 시작 번호·문단 머리 정보 12바이트만 본다.
    struct NumberingDefinition: Equatable {
        let startingIndex: UInt16
        let formats: [String]
        let startingIndexes: [UInt32]
        let paraHeadInfo: [[BYTE]]
    }

    /// 글머리표 정의 하나 (#133).
    ///
    /// `checkChar`와 문서화되지 않은 trailing 바이트는 축이 아니다. 대응 속성이
    /// 없어서가 아니라(`hh:bullet@checkedChar`는 실재하고 매퍼가 읽는다) **포맷
    /// 비대칭** 때문이다 — 바이너리는 표 42대로 고정 WCHAR 필드라 값이 없어도
    /// U+0000 한 자를 담고, HWPX는 선택 속성이라 부재가 곧 빈 문자열이다. 같은
    /// 문서가 포맷마다 다른 값이 되므로 정규화 없이는 축이 될 수 없다.
    struct BulletDefinition: Equatable {
        let char: String
        let info: [BYTE]
        let headCharShapeId: Int32
        let imageId: Int32
    }

    /// 문단 하나의 문단 머리 (표 44 bit 23-27 + 1-based 정의 참조).
    struct ParagraphHeading: Equatable {
        let kind: UInt32
        let level: UInt32
        let definitionId: UInt16
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
    /// 문단 번호 정의 — HWPX `hh:numbering`이 승격돼야 HWP 쌍과 같은 배열이
    /// 선다 (#133). 이 축은 #134·#135와 달리 **11쌍 전부에서 비어 있지 않다**
    /// (HWPX 11종 모두 `hh:numberings`를 갖고 HWP 쌍도 정의 1-2종을 싣는다).
    let numberingDefinitions: [NumberingDefinition]
    /// 글머리표 정의 — noori 1쌍만 값이 있고 나머지 10쌍은 빈 배열 등식이다.
    let bulletDefinitions: [BulletDefinition]
    /// 문단 머리(표 44) — 이 승격 전에도 두 포맷이 같았으므로 이 축은 격차를
    /// 잡지 못한다. 정의 축이 참조를 따라가지 않으므로 참조 배선
    /// (`hh:paraPr`의 `hh:heading` 리맵)이 깨지는 회귀를 여기서 잡는다.
    let paragraphHeadings: [ParagraphHeading]
    /// 구역별 개요 번호 정의 참조(`HwpSectionDef.numberParaShapeId`, 1-based) —
    /// HWPX `hp:secPr@outlineShapeIDRef`가 id 테이블로 리맵돼야 HWP 쌍과 같은
    /// 값이 선다 (#152). 매핑 전에는 HWPX 쪽이 빈 문서 기본값 1이라 noori
    /// (2)에서 갈린다. 구역 첫 문단의 첫 `.section` 컨트롤을 본다 — 헌법주석처럼
    /// 단 정의가 앞서는 저장본도 있어 첫 컨트롤만 보면 안 된다.
    let sectionOutlineNumberingIds: [UInt16]

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
        numberingDefinitions = file.docInfo.idMappings.numberingArray.map { numbering in
            NumberingDefinition(
                startingIndex: numbering.startingIndex,
                formats: numbering.formatArray.map(\.format),
                startingIndexes: numbering.startingIndexArray ?? [],
                paraHeadInfo: numbering.formatArray.map(\.property)
            )
        }
        bulletDefinitions = file.docInfo.idMappings.bulletArray.map {
            BulletDefinition(
                char: $0.char,
                info: $0.info,
                headCharShapeId: $0.headCharShapeId,
                imageId: $0.imageId
            )
        }
        paragraphHeadings = Self.paragraphHeadings(of: file)
        sectionOutlineNumberingIds = file.sectionArray.compactMap { section in
            section.paragraph.first?.ctrlHeaderArray?.lazy.compactMap { ctrl -> UInt16? in
                if case let .section(sectionDef) = ctrl {
                    return sectionDef.numberParaShapeId
                }
                return nil
            }.first
        }
    }

    /// 문단 머리를 문서 순서(표 셀 재귀 포함)로 모은다 — noori의 글머리표
    /// 문단 2개가 표 셀 안이라 최상위 문단만 걸으면 이 축이 비어 버린다.
    /// 머리 없는 문단은 싣지 않는다 (문단 분할 차이에 흔들리지 않게).
    static func paragraphHeadings(of file: HwpFile) -> [ParagraphHeading] {
        let paraShapes = file.docInfo.idMappings.paraShapeArray
        func walk(_ paragraphs: [HwpParagraph]) -> [ParagraphHeading] {
            paragraphs.flatMap { paragraph -> [ParagraphHeading] in
                var headings: [ParagraphHeading] = []
                let shapeId = Int(paragraph.paraHeader.paraShapeId)
                if paraShapes.indices.contains(shapeId) {
                    let property = paraShapes[shapeId].property1Info
                    if property.headingTypeRawValue != 0 {
                        headings.append(ParagraphHeading(
                            kind: property.headingTypeRawValue,
                            level: property.headingLevelRawValue,
                            definitionId: paraShapes[shapeId].numberingOrBulletId
                        ))
                    }
                }
                for ctrl in paragraph.ctrlHeaderArray ?? [] {
                    if case let .table(table) = ctrl {
                        headings += table.cellArray.flatMap { walk($0.paragraphArray) }
                    }
                }
                return headings
            }
        }
        return file.sectionArray.flatMap { walk($0.paragraph) }
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
                let underlineType = shape.property.underlineType
                let run = ResolvedRun(
                    baseSize: shape.baseSize,
                    isBold: shape.property.isBold,
                    isItalic: shape.property.isItalic,
                    faceColor: shape.faceColor,
                    underlineType: underlineType == .undefined2 ? .none : underlineType
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
        expect(numberingDefinitions).to(
            equal(other.numberingDefinitions),
            description: "\(fixtureId) numberingDefinitions"
        )
        expect(bulletDefinitions).to(
            equal(other.bulletDefinitions),
            description: "\(fixtureId) bulletDefinitions"
        )
        expect(paragraphHeadings).to(
            equal(other.paragraphHeadings), description: "\(fixtureId) paragraphHeadings"
        )
        expect(sectionOutlineNumberingIds).to(
            equal(other.sectionOutlineNumberingIds),
            description: "\(fixtureId) sectionOutlineNumberingIds"
        )
    }
}
