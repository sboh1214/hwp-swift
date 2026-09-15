import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 줄 상자보다 큰 글자가 든 문단도 줄을 잃지 않는다 (#202·#198).
    ///
    /// 종전에는 비율·고정 줄 간격을 `minimumLineHeight = maximumLineHeight`로 CT에 못박아,
    /// 상대 크기(표 33)나 고정값 때문에 조판 글꼴이 그 높이에 안 들어가면 CoreText가 프레임에
    /// 줄을 하나도 놓지 않았다 — 측정 높이 0·렌더 0줄로 문단이 통째로 사라지고, 여러 줄 문단은
    /// 마지막 줄이 잘려 나갔다. 지금은 줄 전진량을 CT 밖에서 줄별 상자로 내므로 (#180) CT
    /// 스타일에 상한을 두지 않고, 한글처럼 상자(기본 크기)는 그대로 둔 채 글리프가 넘친다
    /// (한글 12.30 실측: 기본 10pt·상대 크기 250%·비율 100% 줄의 `vertsize` 1000·전진량 10pt).
    final class HwpOversizedGlyphLineTests: XCTestCase {
        /// 상대 크기 250% × 비율 100%: 한 줄 문단이 한 줄로 남고 높이는 기본 크기 10pt다.
        func testRelativeSizeLargerThanThePinnedHeightKeepsTheLine() throws {
            for (relative, percent) in [(200, 100), (250, 100), (250, 130), (170, 100)] {
                let index = try Self.index(relativeSize: UInt8(relative), percent: percent)
                let paragraph = try HwpSynthetic.textParagraph("가나다 ABCD gjpqy")
                let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                    .build(paragraph: paragraph)
                let frame = HwpParagraphLayout().layout(
                    attributedString: built, paraShape: index.paraShapeOrDefault(for: paragraph),
                    columnWidth: 400
                )
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: built, origin: .zero, lineWidth: 400
                )
                expect(frame.lines.count).to(equal(1), description: "\(relative)%·\(percent)% 측정")
                expect(drawn.count).to(equal(1), description: "\(relative)%·\(percent)% 렌더")
                expect(frame.totalHeight).to(beCloseTo(10 * CGFloat(percent) / 100, within: 0.001))
                expect(drawn.first?.baselineOrigin.y).to(beCloseTo(8.5, within: 0.001))
            }
        }

        /// 여러 줄 문단의 뒷줄도 잘리지 않는다 — 렌더 줄들이 문자열 전체를 덮는다.
        func testOversizedGlyphsDoNotDropTrailingLines() throws {
            for (relative, count, width) in [(150, 15, 120), (250, 30, 400), (250, 60, 400)] {
                let index = try Self.index(relativeSize: UInt8(relative), percent: 100)
                let paragraph = try HwpSynthetic.textParagraph(
                    String(repeating: "가", count: count)
                )
                let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                    .build(paragraph: paragraph)
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: built, origin: .zero, lineWidth: CGFloat(width)
                )
                let frame = HwpParagraphLayout().layout(
                    attributedString: built, paraShape: index.paraShapeOrDefault(for: paragraph),
                    columnWidth: CGFloat(width)
                )
                let covered = drawn.reduce(0) { $0 + $1.stringRange.length }
                expect(covered).to(equal(built.length), description: "\(relative)% \(count)자")
                expect(drawn.count).to(beGreaterThanOrEqualTo(2))
                expect(frame.lines.count).to(equal(drawn.count))
                // 전진량은 상자(기본 10pt) × 100% = 10pt — 글리프 크기와 무관하다.
                expect(frame.totalHeight).to(beCloseTo(10 * CGFloat(drawn.count), within: 0.001))
            }
        }

        /// 고정 줄 간격이 글자보다 작아도 (고정 8pt에 24pt 글자) 줄은 전부 놓이고 전진량은 그 값이다.
        func testFixedSpacingSmallerThanTheGlyphKeepsEveryLine() throws {
            let index = try Self.index(relativeSize: 240, percent: 100, fixed: 1600)
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 40))
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: built, origin: .zero, lineWidth: 300
            )
            expect(drawn.count).to(beGreaterThanOrEqualTo(2))
            expect(drawn.reduce(0) { $0 + $1.stringRange.length }).to(equal(built.length))
            for (previous, next) in zip(drawn, drawn.dropFirst()) {
                expect(next.baselineOrigin.y - previous.baselineOrigin.y)
                    .to(beCloseTo(8, within: 0.001))
            }
        }

        // MARK: 헬퍼

        /// 기본 10pt에 상대 크기 `relativeSize`를 준 글자 모양 + 비율(또는 고정) 줄 간격의 인덱스.
        private static func index(
            relativeSize: UInt8, percent: Int, fixed: UInt32? = nil
        ) throws -> HwpIndex {
            var paraShape = CoreHwp.HwpParaShape()
            if let fixed {
                paraShape.property3 = 1
                paraShape.lineSpacing2 = fixed
            } else {
                paraShape.property3 = 0
                paraShape.lineSpacing2 = UInt32(percent)
            }
            return HwpIndex(
                charShapes: [0: try charShape(baseSize: 1000, relativeSize: relativeSize)],
                paraShapes: [0: paraShape], borderFills: [:],
                tabDefs: [:], styles: [:], bullets: [:], numberings: [:], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        /// 표 33 레코드를 직접 만들어 읽는다 — `HwpNumberingHeadingRenderTests.charShape`에 상대
        /// 크기 필드를 더한 것.
        private static func charShape(
            baseSize: Int32, relativeSize: UInt8
        ) throws -> CoreHwp.HwpCharShape {
            var data = Data()
            func append(_ value: some FixedWidthInteger) {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            for _ in 0 ..< 7 {
                append(UInt16(0))
            } // faceId
            data.append(contentsOf: [UInt8](repeating: 100, count: 7)) // faceScaleX
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // faceSpacing
            data.append(contentsOf: [UInt8](repeating: relativeSize, count: 7)) // faceRelativeSize
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // faceLocation
            append(baseSize)
            append(UInt32(0)) // property
            data.append(contentsOf: [0, 0]) // shadow offsets
            for _ in 0 ..< 4 {
                append(UInt32(0))
            } // colors
            return try CoreHwp.HwpCharShape.load(data, CoreHwp.HwpVersion(5, 0, 1, 0))
        }
    }
#endif
