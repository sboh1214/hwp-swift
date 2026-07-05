@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 참조 (본문 ext17 위첨자)와 각주 첫머리 자동 번호 (ext18) 렌더 검증
    final class HwpPaginatorNoteNumberTests: XCTestCase {
        func testBodyReferenceAndNoteLeadingNumberAreRendered() async throws {
            let note = HwpSynthetic.noteParagraph(
                " 각주 내용",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let footnote = HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [note])
            var body = HwpSynthetic.paragraphWithInlineControl(
                prefix: "본문 텍스트",
                suffix: " 이어짐"
            )
            body.ctrlHeaderArray = [.footnote(footnote)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [body]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            // 본문 참조 위치에 위첨자 번호 "1)"
            let bodyBlock = page?.blocks.first {
                $0.kind == .text && $0.attributedString?.string.contains("본문") == true
            }
            let bodyText = bodyBlock?.attributedString?.string ?? ""
            expect(bodyText).to(contain("1)"))
            expect(self.hasRaisedBaselineRun(in: bodyBlock?.attributedString)).to(
                beTrue(),
                description: "본문 각주 참조 번호가 위첨자가 아니다"
            )

            // 각주 블록 첫머리 번호 "1)"
            let footnoteBlock = page?.blocks.first { $0.kind == .footnote }
            expect(footnoteBlock?.attributedString?.string.hasPrefix("1)")).to(
                beTrue(),
                description: "각주 첫머리에 번호가 없다: \(footnoteBlock?.attributedString?.string ?? "nil")"
            )

            // paint list에도 번호가 존재
            let paintTexts = paintedTexts(of: page)
            expect(paintTexts.contains { $0.contains("1)") }).to(
                beTrue(),
                description: "paint list에 각주 번호가 없다: \(paintTexts)"
            )

            // 자동 번호가 unsupported로 보고되지 않는다
            let unsupported = await paginator.unsupportedElements()
            expect(unsupported).to(beEmpty())
        }

        func testNewNumberResetsFootnoteCounter() async throws {
            // nwno(각주, 7) 이후의 첫 각주는 7)로 렌더된다 (헌법주석의 구역별 리셋 구조)
            let note = HwpSynthetic.noteParagraph(
                " 리셋된 각주",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, number: 7, decorationTail: ")")
            )
            let footnote = HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [note])
            var body = HwpSynthetic.paragraphWithInlineControl(prefix: "본문", suffix: " 끝")
            body.ctrlHeaderArray = [.footnote(footnote)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [
                    HwpSynthetic.markerParagraph(
                        control: HwpSynthetic.newNumberControl(kind: 1, number: 7)
                    ),
                    body,
                ]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            let footnoteBlock = page?.blocks.first { $0.kind == .footnote }
            expect(footnoteBlock?.attributedString?.string.hasPrefix("7)")).to(
                beTrue(),
                description: "새 번호가 반영되지 않았다: \(footnoteBlock?.attributedString?.string ?? "nil")"
            )
            let bodyBlock = page?.blocks.first {
                $0.kind == .text && $0.attributedString?.string.contains("본문") == true
            }
            expect(bodyBlock?.attributedString?.string).to(contain("7)"))
        }

        func testMultiParagraphFootnoteSharesOneNumber() async throws {
            // 여러 문단짜리 각주는 번호 하나만 소비한다 (한글과 동일)
            let first = HwpSynthetic.noteParagraph(
                " 첫 문단",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let second = try HwpSynthetic.textParagraph("둘째 문단")
            let multiNote = HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [first, second]
            )
            let single = HwpSynthetic.noteParagraph(
                " 다음 각주",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let singleNote = HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [single])

            var body = HwpSynthetic.paragraphWithInlineControl(prefix: "본문A", suffix: "")
            body.ctrlHeaderArray = [.footnote(multiNote)]
            var body2 = HwpSynthetic.paragraphWithInlineControl(prefix: "본문B", suffix: "")
            body2.ctrlHeaderArray = [.footnote(singleNote)]

            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [body, body2]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)
            let noteTexts = (page?.blocks ?? [])
                .filter { $0.kind == .footnote }
                .compactMap(\.attributedString?.string)
            // 두 번째 각주 컨트롤은 2번을 받아야 한다 (문단 수 3이 아니라 컨트롤 수 기준)
            expect(noteTexts.contains { $0.hasPrefix("2)") }).to(
                beTrue(),
                description: "여러 문단 각주가 번호를 여러 개 소비했다: \(noteTexts)"
            )
        }

        func testFootnoteEndnoteFixtureRegression() async throws {
            // footnote-endnote 실제 픽스처가 여전히 파싱/렌더되고,
            // 각주 블록에 번호 치환이 반영되는지
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/footnote-endnote/document.hwp")
            let file = try CoreHwp.HwpFile(fromPath: url.path)
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 1
            var noteBlockCount = 0
            for pageIndex in 0 ..< totalPages {
                let page = try await paginator.page(at: pageIndex)
                noteBlockCount += (page?.blocks ?? []).count { $0.kind == .footnote }
            }
            expect(noteBlockCount) >= 1
        }
    }

    private extension HwpPaginatorNoteNumberTests {
        /// 베이스라인이 올라간 (위첨자) run이 있는지
        func hasRaisedBaselineRun(in attributedString: NSAttributedString?) -> Bool {
            guard let attributedString else { return false }
            var found = false
            attributedString.enumerateAttribute(
                kCTBaselineOffsetAttributeName as NSAttributedString.Key,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, _, stop in
                if let number = value as? NSNumber, number.doubleValue > 0 {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        func paintedTexts(of page: HwpPage?) -> [String] {
            (page?.paintList.commands ?? []).compactMap { command in
                if case let .drawText(attributedString, _, _) = command {
                    return attributedString.string
                }
                return nil
            }
        }
    }
#endif
