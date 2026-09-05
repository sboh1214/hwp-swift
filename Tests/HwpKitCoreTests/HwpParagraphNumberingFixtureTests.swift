@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 생성의 **실측 핀** (#153).
    ///
    /// 오라클은 셋이다. 헌법주석(`legacy-common-control-property`)은 본문 첫머리에
    /// 한글이 만든 **목차**(구역 0 문단 50-377)를 실어 41개 구역의 1수준 표제 280개가
    /// `I.`·`II.`… 어느 번호를 받는지 적어 두었고, 한글.app이 저장한
    /// `outline-numbering` 쌍은 미리보기 이미지(PrvImage)에 `I.`·`가.`·`1)`·`1.`·`2.`
    /// 라벨을 그려 두었으며, 1,944개 전체 문자열은 커밋된 스냅샷으로 잠근다
    /// (`RECORD_NUMBERING_SNAPSHOTS=1 swift test --filter HwpParagraphNumberingFixture`
    /// 로 재기록 — 레코딩 뒤 의도적으로 실패한다).
    final class HwpParagraphNumberingFixtureTests: XCTestCase {
        private static func fixtureURL(_ id: String, hwpx: Bool = false) -> URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    hwpx ? "CoreHwpTests/HwpxFixtures/\(id)/document.hwpx"
                        : "CoreHwpTests/Fixtures/\(id)/document.hwp"
                )
        }

        private static func fixture(_ id: String, hwpx: Bool = false) throws -> HwpFile {
            try HwpFile(fromPath: fixtureURL(id, hwpx: hwpx).path)
        }

        private static func numbering(of file: HwpFile) -> HwpParagraphNumbering {
            HwpParagraphNumbering.generate(
                sections: file.displaySectionArray, index: HwpIndex(from: file)
            )
        }

        /// 문단 평문 — 개요 수집기와 같은 UTF-16 단위 규칙에 공백 정규화만 얹는다.
        private static func title(of paragraph: HwpParagraph) -> String {
            String(decoding: HwpOutlineCollector.titleUnits(of: paragraph), as: UTF16.self)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }

        private static func snapshotURL(_ id: String) -> URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("ParagraphNumberingSnapshots/\(id).tsv")
        }

        /// 한 문단 한 줄 — 경로·종류·수준·수준별 번호·라벨.
        private static func snapshot(_ numbering: HwpParagraphNumbering) -> String {
            numbering.entries.map { path, number in
                [
                    path.description, number.kind.rawValue, String(number.level),
                    number.numbers.map(String.init).joined(separator: "."), number.text,
                ].joined(separator: "\t")
            }.joined(separator: "\n") + "\n"
        }

        // MARK: - 헌법주석

        /// 1,944개 개요 문단 전부에 번호가 붙고, 이슈가 지목한 13쪽의 첫 1·2·3수준이
        /// `I.`·`1.`·`가.`다 (로마 숫자는 ASCII `I`).
        func testLegacyOutlineParagraphsAreAllNumbered() throws {
            let numbering = Self.numbering(of: try Self.fixture("legacy-common-control-property"))

            expect(numbering.count) == 1944
            expect(numbering.entries.allSatisfy { $0.number.kind == .outline }) == true
            expect(numbering.paths.allSatisfy(\.isTopLevel)) == true
            let first = HwpParagraphPath(sectionIndex: 0, paragraphIndex: 378)
            expect(numbering[first]?.text) == "I."
            expect(numbering[first]?.text.unicodeScalars.first) == "I"
            expect(numbering[HwpParagraphPath(sectionIndex: 0, paragraphIndex: 382)]?.text) == "1."
            expect(numbering[HwpParagraphPath(sectionIndex: 0, paragraphIndex: 387)]?.text) == "가."
            expect(numbering[first]?.numbers) == [1]
            expect(numbering[HwpParagraphPath(sectionIndex: 0, paragraphIndex: 387)]?.numbers)
                == [1, 1, 1]
            var levelCounts: [Int: Int] = [:]
            for entry in numbering.entries {
                levelCounts[entry.number.level, default: 0] += 1
            }
            expect(levelCounts) == [1: 280, 2: 512, 3: 486, 4: 301, 5: 244, 6: 100, 7: 21]
            // 라벨은 수준별 형식 그대로다 — 4·5수준 괄호, 6·7수준 닫는 괄호.
            let byLevel = Dictionary(grouping: numbering.entries, by: \.number.level)
            expect(byLevel[4]?.allSatisfy { $0.number.text.hasPrefix("(") }) == true
            expect(byLevel[6]?.allSatisfy { $0.number.text.hasSuffix(")") }) == true
        }

        /// 헌법주석의 생성 목차 — 구역(조문)마다 1수준이 `I.`부터 다시 시작하고, 280개
        /// 표제의 번호·제목이 우리 생성 결과와 순서대로 일치한다. 41개 구역 정의 중
        /// 첫 구역 것만 이어 매기기(시작 번호 0)이고 나머지는 새 번호라 구역 경계의
        /// 재시작 규칙이 이 문서의 실물이다.
        func testLegacyGeneratedTableOfContentsMatchesLevelOneLabels() throws {
            let file = try Self.fixture("legacy-common-control-property")
            let numbering = Self.numbering(of: file)
            let section = file.displaySectionArray[0]
            let tableOfContents = (50 ... 377).compactMap { paragraphIndex -> (String, String)? in
                let text = Self.title(of: section.paragraph[paragraphIndex])
                guard let space = text.firstIndex(of: " "),
                      text[..<space].hasSuffix("."),
                      text[..<space].dropLast().allSatisfy({ "IVXL".contains($0) })
                else { return nil }
                return (String(text[..<space]), String(text[text.index(after: space)...]))
            }
            expect(tableOfContents.count) == 280

            let levelOne = numbering.entries.filter { $0.number.level == 1 }
            expect(levelOne.count) == tableOfContents.count
            var sectionsRestarting = Set<Int>()
            for (entry, tocEntry) in zip(levelOne, tableOfContents) {
                let paragraph = file.displaySectionArray[entry.path.paragraph.sectionIndex]
                    .paragraph[entry.path.paragraph.paragraphIndex]
                let title = Self.title(of: paragraph)
                expect(entry.number.text).to(equal(tocEntry.0), description: title)
                // 목차 줄은 제목 뒤에 쪽 번호가 붙으므로 제목의 앞부분만 댄다.
                expect(tocEntry.1.hasPrefix(String(title.prefix(8)))).to(
                    beTrue(), description: "\(tocEntry.1) vs \(title)"
                )
                if entry.number.text == "I." {
                    sectionsRestarting.insert(entry.path.paragraph.sectionIndex)
                }
            }
            expect(sectionsRestarting.count) == 41
        }

        /// 1,944개 문자열 전체 — 커밋된 스냅샷과 한 줄씩 같다.
        func testLegacyNumberingMatchesCommittedSnapshot() throws {
            let id = "legacy-common-control-property"
            let actual = Self.snapshot(Self.numbering(of: try Self.fixture(id)))
            let url = Self.snapshotURL(id)
            if ProcessInfo.processInfo.environment["RECORD_NUMBERING_SNAPSHOTS"] == "1" {
                try actual.write(to: url, atomically: true, encoding: .utf8)
                return fail("스냅샷을 기록했다 — diff 리뷰 후 RECORD_NUMBERING_SNAPSHOTS 없이 재실행")
            }
            let expected = try String(contentsOf: url, encoding: .utf8)
            let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
            let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false)
            expect(actualLines.count) == expectedLines.count
            for (line, (expectedLine, actualLine)) in zip(expectedLines, actualLines).enumerated()
                where expectedLine != actualLine
            {
                return fail("스냅샷 \(line + 1)행: 기대 \(expectedLine) / 실제 \(actualLine)")
            }
        }

        // MARK: - 한글.app 저장본

        /// `outline-numbering` — 한글.app이 그린 미리보기 라벨과 같다: 사용자 정의 개요
        /// 정의로 `I.`·`가.`·`1)`, 기본 정의로 `1.`·`2.`. HWPX 쌍도 같다.
        func testOutlineNumberingFixtureMatchesTheHancomPreviewLabels() throws {
            for hwpx in [false, true] {
                let numbering = Self.numbering(of: try Self.fixture("outline-numbering", hwpx: hwpx))
                expect(numbering.entries.map(\.number.text)).to(
                    equal(["I.", "가.", "1)", "1.", "2."]), description: hwpx ? "HWPX" : "HWP"
                )
                expect(numbering.entries.map(\.number.numbers)) == [[1], [1, 1], [1, 1, 1], [1], [2]]
                expect(numbering.entries.map(\.number.kind)) == [
                    .outline, .outline, .outline, .numbering, .numbering,
                ]
                expect(numbering.entries.map(\.number.definitionIndex)) == [1, 1, 1, 0, 0]
                expect(numbering.paths.map(\.description)) == [
                    "s0/p1", "s0/p2", "s0/p3", "s0/p5", "s0/p6",
                ]
            }
        }

        /// HWP·HWPX 쌍은 같은 번호를 낸다 — 정의 배열·구역 참조·문단 머리가 등가라는
        /// 파서 층의 대조(`HwpxHwpEquivalenceTests`)를 생성 결과까지 잇는다.
        func testHwpxPairsGenerateTheSameNumbersAsTheirHwpSources() throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/HwpxFixtures")
            let ids = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { FileManager.default.fileExists(atPath: Self.fixtureURL($0, hwpx: true).path) }
                .sorted()
            expect(ids.count) >= 12
            var numbered = 0
            for id in ids {
                let hwp = Self.numbering(of: try Self.fixture(id))
                let hwpx = Self.numbering(of: try Self.fixture(id, hwpx: true))
                expect(hwpx).to(equal(hwp), description: id)
                numbered += hwp.count
            }
            // 쌍 가운데 번호 문단을 가진 것은 `outline-numbering`(5)뿐이다.
            expect(numbered) == 5
        }

        /// noori — 탐색 목록의 개요 문단 4개(표 셀 안, 스타일 이름 `개요 3`)는 문단
        /// 머리 종류가 개요(1)가 아니라 없음(0)·글머리표(3)라 개요 **번호**는 없다 —
        /// 스타일 이름 폴백은 탐색 목록(`HwpOutlineCollector`)의 규칙이지 번호의
        /// 규칙이 아니다. 한글도 그 문단에 글머리표 `-`만 그린다.
        func testNooriStyleNamedHeadingsInsideCellsGetNoNumber() throws {
            let file = try Self.fixture("noori")
            let index = HwpIndex(from: file)
            var styleNamedHeadings = 0
            func visit(_ paragraph: HwpParagraph) {
                let style = index.style(id: UInt32(paragraph.paraHeader.paraStyleId))
                if style?.styleLocalName.hasPrefix("개요") == true {
                    styleNamedHeadings += 1
                    let kind = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))?
                        .property1Info.headingTypeRawValue
                    expect(kind).toNot(equal(1))
                }
                for control in paragraph.ctrlHeaderArray ?? [] {
                    for (child, _) in HwpPaginator.childParagraphs(of: control) {
                        visit(child)
                    }
                }
            }
            for section in file.displaySectionArray {
                for paragraph in section.paragraph {
                    visit(paragraph)
                }
            }
            expect(styleNamedHeadings) == 4
            expect(Self.numbering(of: file).count) == 0
        }

        /// 개요·번호 문단이 없는 픽스처는 빈 표다.
        func testFixturesWithoutHeadingsProduceNoNumbers() throws {
            for id in ["multi-section", "plain-text-minimal", "bookmark", "footnote-endnote"] {
                expect(Self.numbering(of: try Self.fixture(id)).count).to(equal(0), description: id)
            }
        }
    }
#endif
