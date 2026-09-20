import CoreGraphics
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 표 셀·글상자 안 글자와 쪽 번호의 세로 자리를 한컴오피스 한글이 **그린** 자리에 맞춘다 (#193).
///
/// 오라클은 한글 12.30.0 (macOS, 2026-09-18)이 같은 문서를 `PDF로 저장하기…`로 내보낸
/// PDF의 텍스트 베이스라인(PyMuPDF `origin.y`)이다. 한글 PDF 좌표는 0.12pt 장치 양자화라
/// 허용 오차를 그만큼 둔다. 셀·글상자의 줄 상자 모델은 글꼴 지표와 무관하므로(#178)
/// 결정론 글꼴(`HwpFontResolver.testDeterministic`)로도 같은 값이 나온다 — 쪽 번호만 글꼴
/// descent의 함수라 관계식으로 잠근다.
///
/// 수정 전 격차(이슈 표): 제목 표 −5.33~−5.35·표 셀 −1.29~−2.58·문서 하단 표 −3.14·
/// 쪽 번호 −31.67pt. 원인은 셋이다 — 셀 세로 정렬이 마지막 줄의 줄 간격 여분을 내용에
/// 넣었고(`HwpContainerContentExtent`), 글자처럼 취급 표의 바깥 위 여백 1.40pt를 쓰지
/// 않았고(`HwpObjectAnchorGeometry.OuterMargins`), 쪽 번호를 꼬리말 영역 위에 놓았다.
final class FixtureContainerTextPositionTests: XCTestCase {
    /// 한글 PDF의 0.12pt 양자화 + 부동소수 잔차.
    private static let tolerance = 0.13

    private static func document(_ id: String, file: String = #file) async throws -> HwpDocument {
        let url = FixtureRoot.url(from: file)
            .appendingPathComponent(id)
            .appendingPathComponent("document.hwp")
        return try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
    }

    /// 쪽의 그려지는 줄 가운데 글자가 `prefix`로 시작하는 첫 줄의 베이스라인.
    private static func baseline(of prefix: String, in page: HwpPage) -> Double? {
        for command in page.paintList.commands {
            guard case let .drawText(attributedString, origin, lineWidth) = command
            else { continue }
            for line in HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            ) {
                let text = (attributedString.string as NSString).substring(with: line.stringRange)
                if text.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
                    return Double(line.baselineOrigin.y)
                }
            }
        }
        return nil
    }

    /// noori 1쪽 — 가운데 정렬 셀(줄 간격 120·140·130%)과 글자처럼 취급 1칸 제목 표(바깥
    /// 위 여백 140, 4문단 150%·위 간격 6pt).
    func testNooriFirstPageCellBaselinesMatchHancom() async throws {
        let document = try await Self.document("noori")
        let page = document.pages[0]
        let expected: [(String, Double)] = [
            ("보도일시", 155.88), ("배포일시", 178.08), ("담당부서", 178.08),
            ("담당과장", 201.60), ("장인숙", 201.60),
            ("우리가 독자 개발하여", 252.12), ("국민이 정한 그 이름은", 279.12),
            ("- “세상”의 옛말로", 310.44), ("- 명칭공모전에", 340.44),
        ]
        for (prefix, hancom) in expected {
            expect(Self.baseline(of: prefix, in: page))
                .to(beCloseTo(hancom, within: Self.tolerance), description: prefix)
        }
        // 제목 표는 줄 상단(캐시 vertpos 15475 → 225.60) + 바깥 위 여백 1.40에 놓인다 —
        // 한글 PDF의 이중선 테두리 가운데가 226.86~226.98이다.
        let titleTable = try XCTUnwrap(page.blocks.first {
            $0.kind == .table && $0.frame.height > 120
        })
        expect(titleTable.frame.minY).to(beCloseTo(227.00, within: 0.01))
    }

    /// noori 2·3쪽 — 문서 하단 2칸 표(바깥 위 여백 140, 9pt 140% 두 줄)와 붙임 표의 가운데
    /// 정렬 셀(120%).
    func testNooriLaterPageCellBaselinesMatchHancom() async throws {
        let document = try await Self.document("noori")
        let second: [(String, Double)] = [
            ("이 자료에 대하여", 738.00), ("과학기술정보통신부 용찬재", 750.60),
        ]
        for (prefix, hancom) in second {
            expect(Self.baseline(of: prefix, in: document.pages[1]))
                .to(beCloseTo(hancom, within: Self.tolerance), description: prefix)
        }
        let third: [(String, Double)] = [
            ("한국형발사체(누리호)와 시험발사체", 100.56),
            ("47.2 m", 658.92), ("3.5 m", 682.20), ("200 톤", 705.48),
            ("1.5 톤", 728.76), ("3단", 750.84),
        ]
        for (prefix, hancom) in third {
            expect(Self.baseline(of: prefix, in: document.pages[2]))
                .to(beCloseTo(hancom, within: Self.tolerance), description: prefix)
        }
    }

    /// `text-box` 떠 있는 글상자 — 가운데 정렬, 여백 2.83pt, 10pt 160% 두 문단.
    func testTextBoxBaselinesMatchHancom() async throws {
        let page = try await Self.document("text-box").pages[0]
        expect(Self.baseline(of: "Text box fixture", in: page))
            .to(beCloseTo(142.20, within: Self.tolerance))
        expect(Self.baseline(of: "inside box", in: page))
            .to(beCloseTo(158.28, within: Self.tolerance))
    }

    /// 쪽 번호 — 아래 위치는 꼬리말 영역 바닥 − 글꼴 descent, 위 위치는 머리말 영역 위 +
    /// 글자 크기 − descent. 한글 PDF: noori 811.20(= 813.54 − 함초롬돋움 2.30),
    /// section-marks 위쪽 '- 9 -' 64.44(= 56.68 + 10 − 2.30). 결정론 글꼴은 descent가 달라
    /// 관계식으로 잠근다.
    func testPageNumbersHangFromTheChromeAreaEdges() async throws {
        let noori = try await Self.document("noori")
        for page in noori.pages {
            let number = try XCTUnwrap(Self.pageNumber(in: page))
            expect(number.baseline + number.descent).to(beCloseTo(813.54, within: 0.01))
            expect(number.size).to(beCloseTo(10, within: 0.01))
        }
        let marks = try await Self.document("section-marks")
        let top = try XCTUnwrap(Self.pageNumber(in: marks.pages[1]))
        expect(top.text) == "- 9 -"
        expect(top.baseline - top.size + top.descent).to(beCloseTo(56.68, within: 0.01))
    }

    private struct PageNumber {
        let text: String
        let baseline: CGFloat
        let descent: CGFloat
        let size: CGFloat
    }

    private static func pageNumber(in page: HwpPage) -> PageNumber? {
        guard let block = page.blocks.first(where: {
            $0.role == .pageChrome && $0.kind == .text
        }), let string = block.attributedString,
        let line = HwpDrawnTextLayout.lines(
            attributedString: string, origin: block.frame.origin, lineWidth: block.frame.width
        ).first
        else { return nil }
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line.line, nil, &descent, nil)
        let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
        let size = runs.reduce(CGFloat(0)) { size, run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let font = attributes[kCTFontAttributeName] else { return size }
            return max(size, CTFontGetSize(font as! CTFont)) // swiftlint:disable:this force_cast
        }
        return PageNumber(
            text: string.string, baseline: line.baselineOrigin.y, descent: descent, size: size
        )
    }
}
