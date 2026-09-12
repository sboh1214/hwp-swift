@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 생성의 **실측 핀** (#153).
    ///
    /// 오라클은 넷이다. 헌법주석(`legacy-common-control-property`)은 본문 첫머리에
    /// 한글이 만든 **목차**(구역 0 문단 50-377)를 실어 41개 구역의 1수준 표제 280개가
    /// `I.`·`II.`… 어느 번호를 받는지 적어 두었고, 한글.app이 저장한
    /// `outline-numbering` 쌍은 미리보기 이미지(PrvImage)에 `I.`·`가.`·`1)`·`1.`·`2.`
    /// 라벨을 그려 두었으며, `numbering-sequence` 쌍은 정의 6종·구역 3개·표 셀의
    /// 라벨 20개를 같은 세션의 복사 텍스트로 남겼고, 1,944개 전체 문자열은 커밋된
    /// 스냅샷으로 잠근다
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

        /// HWPX manifest 가운데 쌍을 잇는 열쇠만 읽는다 (`HwpxFixtureRenderTests`와
        /// 같은 규약 — 디렉터리 이름이 아니라 `sourceHwpFixture`가 쌍이다).
        private struct HwpxPairManifest: Decodable {
            let id: String
            let sourceHwpFixture: String?
        }

        /// HWP·HWPX 쌍은 같은 번호를 낸다 — 정의 배열·구역 참조·문단 머리가 등가라는
        /// 파서 층의 대조(`HwpxHwpEquivalenceTests`)를 생성 결과까지 잇는다.
        func testHwpxPairsGenerateTheSameNumbersAsTheirHwpSources() throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/HwpxFixtures")
            let manifests = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .sorted()
                .compactMap { id -> HwpxPairManifest? in
                    let url = root.appendingPathComponent("\(id)/manifest.json")
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return try JSONDecoder().decode(HwpxPairManifest.self, from: Data(contentsOf: url))
                }
            expect(manifests.count) >= 18
            var numbered = 0
            for manifest in manifests {
                guard let pairId = manifest.sourceHwpFixture else {
                    return fail("[\(manifest.id)] no HWP pair (sourceHwpFixture)")
                }
                let hwp = Self.numbering(of: try Self.fixture(pairId))
                let hwpx = Self.numbering(of: try Self.fixture(manifest.id, hwpx: true))
                expect(hwpx).to(equal(hwp), description: manifest.id)
                numbered += hwp.count
            }
            // 쌍 가운데 번호 문단을 가진 것은 `outline-numbering`(5)과
            // `numbering-sequence`(20)다.
            expect(numbered) == 25
        }

        /// `outline-numbering` 둘째 정의의 9·10수준 형식 — 한글.app 12.30 개요 번호 모양
        /// 대화상자 미리보기 실측 문자열을 조립기에 박는다. 문단 수준 비트는 3비트(최대
        /// 8수준)라 문서 순회로는 닿지 않으므로 조립기를 직접 부른다.
        func testOutlineNumberingFixtureLevelPathsMatchTheHancomPreview() throws {
            for hwpx in [false, true] {
                let file = try Self.fixture("outline-numbering", hwpx: hwpx)
                let custom = try XCTUnwrap(file.docInfo.idMappings.numberingArray.last)
                let path = HwpNumberingLabelFormatter.text(
                    definition: custom, level: 9, numbers: Array(repeating: 1, count: 9)
                )
                expect(path).to(equal("I.가.1.가.1.가.①.㉮.ㄱ)"), description: hwpx ? "HWPX" : "HWP")
                let tenth = HwpNumberingLabelFormatter.text(
                    definition: custom, level: 10, numbers: Array(repeating: 1, count: 10)
                )
                expect(tenth).to(equal("ㄱ.I0)"), description: hwpx ? "HWPX" : "HWP")
                // 같은 정의의 3수준 형식 `^3)`은 문단 수준보다 얕은 참조가 없으니 그대로다.
                expect(HwpNumberingLabelFormatter.text(definition: custom, level: 3, numbers: [2, 3, 4]))
                    == "4)"
            }
        }

        /// `numbering-sequence` — 한글.app 12.30이 그린 라벨(같은 세션에서 모두 선택 ·
        /// 복사하기로 받은 텍스트)과 문단마다 같다. 정의별 목록·시작 번호 0의 이어
        /// 받기·수준별 배열 우선·건너뛴 수준·구역 경계·표 셀 순서를 한 문서로 잠근다.
        func testNumberingSequenceFixtureMatchesTheHancomCopiedLabels() throws {
            let expected: [(path: String, text: String, title: String)] = [
                ("s0/p1", "1.", "Outline one"), ("s0/p2", "가.", "Outline one-one"),
                ("s0/p3", "1.", "Numbered A one"), ("s0/p4", "2.", "Numbered A two"),
                ("s1/p0", "3.", "Numbered A three"), ("s1/p1", "나.", "Outline two"),
                ("s1/p2", "가)", "Outline two-one-one"), ("s1/p3", "1.", "Numbered B five"),
                ("s1/p4", "1)", "Numbered B five-x-one"), ("s1/p5", "나.", "Numbered B five-one"),
                ("s1/p6", "2.", "Numbered B six"), ("s1/p7", "3.", "Numbered A continue"),
                ("s1/p8", "2.", "Outline three"), ("s2/p0", "7.", "Section three outline"),
                ("s2/p1", "4.", "Section three numbered"), ("s2/p2", "5.", ""),
                ("s2/p2/c0/n0", "9.", "Cell one"), ("s2/p2/c0/n1", "10.", "Cell two"),
                ("s2/p3", "6.", "After table numbered"), ("s2/p4", "11.", "Numbered restart nine"),
            ]
            for hwpx in [false, true] {
                let file = try Self.fixture("numbering-sequence", hwpx: hwpx)
                let numbering = Self.numbering(of: file)
                let format = hwpx ? "HWPX" : "HWP"
                expect(numbering.paths.map(\.description)).to(
                    equal(expected.map(\.path)), description: format
                )
                expect(numbering.entries.map(\.number.text)).to(
                    equal(expected.map(\.text)), description: format
                )
                for (entry, expectation) in zip(numbering.entries, expected) {
                    var paragraph = file.displaySectionArray[entry.path.paragraph.sectionIndex]
                        .paragraph[entry.path.paragraph.paragraphIndex]
                    for step in entry.path.steps {
                        let control = paragraph.ctrlHeaderArray?[step.controlIndex]
                        paragraph = HwpPaginator.childParagraphs(of: try XCTUnwrap(control))[step.childIndex].0
                    }
                    expect(Self.title(of: paragraph)).to(
                        equal(expectation.title), description: "\(format) \(entry.path)"
                    )
                }
                // 정의별 목록 — 정의 3(목록 B)은 정의 6(셀)의 목록을 사이에 두고 잇는다.
                expect(numbering.entries.map(\.number.definitionIndex)) == [
                    0, 0, 1, 1, 1, 3, 3, 2, 2, 2, 2, 2, 3, 4, 2, 2, 5, 5, 2, 5,
                ]
                expect(numbering.entries.map(\.number.numbers)) == [
                    [1], [1, 1], [1], [2], [3], [1, 2], [1, 2, 1, 1], [1], [1, 1, 1], [1, 2],
                    [2], [3], [2], [7], [4], [5], [9], [10], [6], [11],
                ]
            }
        }

        /// noori — 탐색 목록의 개요 문단 4개(표 셀 안, 스타일 이름 `개요 3`)는 문단
        /// 머리 종류가 개요(1)가 아니라 없음(0)·글머리표(3)라 개요 **번호**는 없다 —
        /// 스타일 이름 폴백은 탐색 목록(`HwpOutlineCollector`)의 규칙이지 번호의
        /// 규칙이 아니다. 한글도 그 문단에 글머리표 `-`만 그린다.
        func testNooriStyleNamedHeadingsInsideCellsGetNoNumber() throws {
            let file = try Self.fixture("noori")
            let index = HwpIndex(from: file)
            var headingKinds: [UInt32?] = []
            func visit(_ paragraph: HwpParagraph) {
                let style = index.style(id: UInt32(paragraph.paraHeader.paraStyleId))
                if style?.styleLocalName.hasPrefix("개요") == true {
                    headingKinds.append(
                        index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))?
                            .property1Info.headingTypeRawValue
                    )
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
            // 실측 순서대로 없음·없음·글머리표·글머리표 — nil(문단 모양 유실)도 잡는다.
            expect(headingKinds) == [0, 0, 3, 3]
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
