import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글줄 앞 자리 차지 표(#190) 합성 테스트의 공용 빌더 —
    /// `HwpFloatingTablePrecedesTextTests`·`HwpFloatingTablePrecedesTextReviewTests`가 함께 쓴다.
    enum FloatingTablePrecedesTextSupport {
        /// 캐시 없는 본문 문단 — 절대 캐시 모드가 아닌 저장본처럼 흐름 배치를 탄다.
        static func flow(_ text: String) throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.textParagraph(text)
        }

        /// 컨트롤 문자 뒤에 `table anchor`가 이어지는 문단 (`line-shapes` 실물과 같은 꼴) —
        /// 30pt 행 `rowCount`개짜리 자리 차지 표를 품는다.
        static func host(
            rowCount: Int,
            margins: [CoreHwp.HWPUNIT16] = [283, 283, 283, 283],
            textWrap: CoreHwp.HwpCommonCtrlTextWrap = .topAndBottom,
            treatAsChar: Bool = false,
            verticalOffset: Int32 = 0,
            pageBreakProperty: UInt32 = 2
        ) throws -> CoreHwp.HwpParagraph {
            var host = paragraphWithInlineControl(suffix: "table anchor")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000,
                    rowHeights: Array(repeating: 3000, count: rowCount),
                    property: pageBreakProperty,
                    cellParagraphs: try (0 ..< rowCount).map {
                        [[try HwpSynthetic.textParagraph("행 \($0)")]]
                    }
                ),
                treatAsChar: treatAsChar,
                verticalOffset: verticalOffset,
                textWrap: textWrap,
                margins: margins
            ))]
            return host
        }

        /// 컨트롤 문자(코드 11) 뒤에 `suffix`가 이어지는 캐시 없는 문단.
        static func paragraphWithInlineControl(suffix: String) -> CoreHwp.HwpParagraph {
            HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: suffix)
        }

        static func paginator(
            columns: Int = 1,
            pageHeight: UInt32 = 84188,
            bodyParagraphs: [CoreHwp.HwpParagraph]
        ) -> HwpPaginator {
            var controls: [CoreHwp.HwpCtrlId] = [
                .section(HwpSynthetic.sectionDef(pageHeight: pageHeight)),
            ]
            if columns > 1 {
                controls.append(.column(HwpSynthetic.column(count: columns, spacing: 1134)))
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: controls, bodyParagraphs: bodyParagraphs
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 본문 블록의 종류·문자열·프레임·표 행 수. 첫 쪽의 첫 블록은 구역 정의를 실은
        /// 빈 문서 템플릿 문단(16pt)이다 — 본문 상단을 그 블록의 top으로 읽는다.
        struct Placed {
            let kind: HwpBlockKind
            let text: String
            let frame: CGRect
            let rowCount: Int
        }

        static func blocks(
            of paginator: HwpPaginator, page: Int = 0
        ) async throws -> [Placed] {
            let rendered = try await paginator.page(at: page)
            let unwrapped = try XCTUnwrap(rendered)
            return unwrapped.blocks.filter { $0.role == .body }.map { block in
                let rows: Int = if case let .table(frame)? = block.payload {
                    frame.rows.count
                } else {
                    0
                }
                return Placed(
                    kind: block.kind,
                    text: (block.attributedString?.string ?? "")
                        .replacingOccurrences(of: "\r", with: ""),
                    frame: block.frame,
                    rowCount: rows
                )
            }
        }
    }
#endif
