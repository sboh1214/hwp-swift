import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 합성 조립·페이지네이션 헬퍼 — 클래스 본문이 SwiftLint type_body_length
    /// 상한(400줄)에 닿아 갈라 뒀다.
    enum FootnoteContinuationSupport {
        static let pitch: CGFloat = 11.72
        static let box: CGFloat = 9.0
        static let overhead: CGFloat = HwpRenderTuning.Footnote.dividerDefaultMarginTop
            + HwpRenderTuning.Footnote.dividerDefaultMarginBottom

        // MARK: - 합성 조립

        static func lineSegPayload(
            _ lines: [(location: Int32, height: Int32, spacing: Int32)],
            property: UInt32 = 0x60000
        ) -> Data {
            var payload = Data()
            for line in lines {
                withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.location.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(765).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: line.spacing.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(42520).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: property.littleEndian) { payload.append(contentsOf: $0) }
            }
            return payload
        }

        /// 각주 줄 캐시 — 세로 위치 목록 (HWPUNIT, 각주 시작 기준). 줄 높이 900·간격 272.
        static func noteLines(
            _ locations: [Int32]
        ) -> [(location: Int32, height: Int32, spacing: Int32)] {
            locations.map { (location: $0, height: 900, spacing: 272) }
        }

        /// 자동 번호 마커로 시작하는 각주 첫 문단 + 줄 캐시. 줄바꿈 문자로 CT 줄 수를
        /// 캐시 줄 수와 같게 고정한다 (조각 문자열 대응이 비례 근사라 어긋나면 흔들린다).
        static func note(
            lines texts: [String], locations: [Int32]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = HwpSynthetic.noteParagraph(
                " " + texts.joined(separator: "\n"),
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                lineSegPayload(noteLines(locations))
            )
            return paragraph
        }

        /// 각주의 뒤 문단 (마커 없음) + 줄 캐시.
        static func notePlainParagraph(
            _ text: String, locations: [Int32]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.textParagraph(text)
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                lineSegPayload(noteLines(locations))
            )
            return paragraph
        }

        /// 각주 참조 마커를 `noteCount`개 가진 한 줄 본문 문단 — 세로 위치 `location`.
        static func host(
            at location: Int32, notes: [[CoreHwp.HwpParagraph]]
        ) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [(characters: 5, markers: Array(repeating: 17, count: notes.count))],
                segments: [(location: location, height: 1000, textStart: 0)]
            )
            host.ctrlHeaderArray = notes.map {
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: $0))
            }
            return host
        }

        /// 절대 캐시 모드 문서 — 첫 loc > 0인 캐시 문단이 다수여야 한다 (감지 규칙).
        static func paginate(
            _ body: [CoreHwp.HwpParagraph],
            footnoteNumberingMode: UInt32 = 0
        ) -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(
                    footnoteNumberingMode: footnoteNumberingMode
                ))],
                bodyParagraphs: body
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 다음 쪽 본문 — 세로 위치가 되돌아가 한글의 쪽 절단점이 된다.
        static func nextPageBody(bottomAt location: Int32? = nil) throws -> [CoreHwp.HwpParagraph] {
            var body = [try HwpSynthetic.lineSegParagraph(
                "다음 쪽 문단", segments: [(location: 2720, height: 1500)]
            )]
            if let location {
                body.append(try HwpSynthetic.lineSegParagraph(
                    "다음 쪽 아래 문단", segments: [(location: location, height: 1000)]
                ))
            }
            return body
        }

        static func footnoteBlocks(on page: HwpPage?) -> [HwpFootnoteBlock] {
            (page?.blocks ?? []).compactMap { block in
                if case let .footnote(note) = block.payload {
                    return note
                }
                return nil
            }
        }

        static func text(_ block: HwpFootnoteBlock) -> String {
            block.paragraphs.map(\.attributedString.string).joined()
        }

        /// 앞·뒤 장식 문자만 지정한 각주 모양 — 구역마다 번호 라벨이 달라지는 문서를
        /// 재현한다. 구분선 값은 건드리지 않아 기본 여백이 그대로 쓰인다.
        static func footnoteShape(
            head: Character?, tail: Character?
        ) -> CoreHwp.HwpFootnoteShape {
            var shape = CoreHwp.HwpSectionDef().footNoteShape
            shape.decorationHeadRawValue = head?.utf16.first ?? 0
            shape.decorationTailRawValue = tail?.utf16.first ?? 0
            return shape
        }

        /// 지정 폭의 A4 쪽 기하 (단위 테스트용) — 구역이 바뀌며 폭이 달라지는 문서를
        /// 페이지네이터 없이 재현한다.
        static func geometry(contentWidth: CGFloat) -> HwpPageGeometry {
            let frame = CGRect(x: 72, y: 72, width: contentWidth, height: 698)
            return HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: frame,
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [frame]
            )
        }

        static func contentBottom(of page: HwpPage) -> CGFloat {
            page.size.height - page.margins.bottom
        }

        /// host 줄 상자 아래에서 본문 하단까지 `available`pt (구분선 여백 제외) 를 남기는
        /// host 세로 위치. 본문 상단 56.68pt·하단 799.36pt (sectionDef 기본 쪽).
        static func hostLocation(leaving available: CGFloat) -> Int32 {
            let contentHeight: CGFloat = 841.88 - 56.68 - 42.52
            let boxBottom = contentHeight - overhead - available
            return Int32((boxBottom * 100).rounded()) - 1000
        }
    }
#endif
