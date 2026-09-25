import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글자처럼 취급 개체 **마커의 글자 모양 크기**는 줄 상자에 들지 않고 비율 여분의 기준에만
    /// 든다 (#217).
    ///
    /// 개체 마커 run(`HwpTextRunBuilder.appendControlMarker`)은 자기 글자 모양의 기본 크기를
    /// 싣는다. 한글은 그 크기를 줄 공간을 **예약한** 마커(개체)와 예약하지 **않은** 마커(책갈피·
    /// 필드 표식·자리 차지 개체 앵커)에서 다르게 쓴다 — 전자는 비율 줄 간격의 여분(`spacing`)
    /// 기준에만, 후자는 글자처럼 줄 상자(`vertsize`)와 여분 기준 둘 다에. 종전에는 둘을 가르지
    /// 않아 개체 마커의 글자 모양이 본문보다 크면 줄 상자가 마커 크기로 부풀었다.
    ///
    /// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-24)이 함초롬바탕 10pt 글·160% 합성
    /// HWPX를 다시 저장한 줄 캐시(`vertsize`·`baseline`·`spacing`)다 — 이슈의 K1·K3·K5·K7
    /// 표본과 `inline-object-marker-size` 픽스처 쌍의 문단 (`FixtureInlineObjectMarkerSizeTests`
    /// 가 그 쌍 전체를 조판해 한글 자리에 잠근다). 한글 문서의 줄 상자는 글꼴 지표의 함수가
    /// 아니라 입력은 Helvetica로 조판한다.
    final class HwpInlineObjectMarkerLineBoxTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private static let ratio = HwpRenderTuning.Text.baselineAnchorRatio
        private static let percent160 = Fixtures.rule(.percent, 160)

        // MARK: 줄 공간을 예약한 개체 마커

        /// 10pt 글에 개체를 싣는 마커의 글자 모양이 크면 — 줄 상자는 글자·개체 가운데 큰 것,
        /// 여분은 마커 기준이다 (한글 캐시 `vertsize`/`baseline`/`spacing`): 40pt 마커의
        /// 20pt 그림(K3) 2000/1700/2400, 8pt 그림(K7) 1000/850/2400, 20pt 마커의 8pt 그림
        /// 1000/850/1200, 바깥 여백 위 7·아래 3의 20pt 그림(바깥 상자 30) 3000/2550/2400.
        /// 종전에는 넷 다 상자가 마커 크기(40·40·20·40)였다 — K3 베이스라인이 17pt, K7이
        /// 25.5pt 아래였다.
        func testObjectMarkerSizeStaysOutOfTheLineBox() {
            let rows = [
                MarkerRow(marker: 40, object: 20, box: 20, share: 24),
                MarkerRow(marker: 40, object: 8, box: 10, share: 24),
                MarkerRow(marker: 20, object: 8, box: 10, share: 12),
                MarkerRow(marker: 40, object: 30, box: 30, share: 24),
            ]
            for row in rows {
                let label = "마커 \(row.marker)pt · 개체 \(row.object)pt"
                let string = Self.objectLine(marker: row.marker, objectHeight: row.object)
                let metrics = Self.metrics(of: string)
                expect(metrics.baseFontSize).to(equal(10), description: label)
                expect(metrics.objectMarkerBaseFontSize).to(equal(row.marker), description: label)
                expect(metrics.boxHeight).to(equal(row.box), description: label)
                expect(metrics.textBoxHeight).to(equal(row.marker), description: label)
                expect(metrics.baselineAnchor)
                    .to(beCloseTo(Self.ratio * row.box, within: 0.0001), description: label)
                // 렌더와 측정이 같은 상자·전진량을 쓴다.
                expect(Fixtures.baselines(string)).to(beCloseTo(
                    [Double(Fixtures.blockTop + Self.ratio * row.box)], within: 0.001
                ), description: label)
                let frame = Self.measure(string, rule: Self.percent160)
                expect(frame.lines.map(\.boxHeight)).to(equal([row.box]), description: label)
                expect(Double(frame.totalHeight))
                    .to(beCloseTo(Double(row.box + row.share), within: 0.001), description: label)
            }
        }

        /// 글자가 마커보다 크면 종전과 같다 — 40pt 글 + 10pt 마커의 20pt 그림(C5) 4000/3400/2400.
        func testTextLargerThanTheMarkerStillSetsTheBox() {
            let text = Fixtures.attributes(size: 40)
            let output = NSMutableAttributedString(string: "ab", attributes: text)
            output.append(Self.marker(height: 20, attributes: Fixtures.attributes(size: 10)))
            let string = Fixtures.applying(Self.percent160, to: output)
            let metrics = Self.metrics(of: string)
            expect(metrics.boxHeight) == 40
            expect(metrics.textBoxHeight) == 40
            expect(Double(Self.measure(string, rule: Self.percent160).totalHeight))
                .to(beCloseTo(64, within: 0.001))
        }

        /// 여분 기준은 마커의 **상대크기 적용 전** 기본 크기다 — 40pt · 50% 마커(실제 20pt
        /// 글꼴)의 8pt 그림 줄도 여분 2400(R1).
        func testRelativeSizeMarkerSharesByItsBaseSize() {
            let output = NSMutableAttributedString(
                string: "ab", attributes: Fixtures.attributes(size: 10)
            )
            output.append(Self.marker(
                height: 8, attributes: Fixtures.attributes(size: 20, baseSize: 40)
            ))
            let string = Fixtures.applying(Self.percent160, to: output)
            expect(Self.metrics(of: string).boxHeight) == 10
            expect(Double(Self.measure(string, rule: Self.percent160).totalHeight))
                .to(beCloseTo(10 + 24, within: 0.001))
        }

        /// 한 줄의 두 개체 — 상자는 큰 개체, 여분은 큰 마커 기준 (W1: 40pt 마커의 8pt 그림 +
        /// 20pt 마커의 12pt 그림 → 1200/1020/2400).
        func testTwoObjectsTakeTheTallerObjectAndTheLargerMarker() {
            let output = NSMutableAttributedString(
                string: "ab", attributes: Fixtures.attributes(size: 10)
            )
            output.append(Self.marker(height: 8, attributes: Fixtures.attributes(size: 40)))
            output.append(
                NSAttributedString(string: " ", attributes: Fixtures.attributes(size: 10))
            )
            output.append(Self.marker(height: 12, attributes: Fixtures.attributes(size: 20)))
            let string = Fixtures.applying(Self.percent160, to: output)
            let metrics = Self.metrics(of: string)
            expect(metrics.boxHeight) == 12
            expect(metrics.objectMarkerBaseFontSize) == 40
            expect(Double(Self.measure(string, rule: Self.percent160).totalHeight))
                .to(beCloseTo(12 + 24, within: 0.001))
        }

        /// 줄 간격 종류마다 상자는 개체·글자 가운데 큰 것이다 (한글 실측 S1~S5): 40pt 마커의 20pt
        /// 그림 줄이 고정 30 → 30(`spacing` 1000), 여백만 5 → 25, 최소 30 → 30, 비율 100 → 20;
        /// 8pt 그림 줄이 최소 12 → 12(`spacing` 200 — 상자 10).
        func testEveryLineSpacingKindAppliesToTheObjectBox() {
            let tall: [Fixtures.RuleCase<CGFloat>] = [
                .init(.fixed, 30, 30), .init(.marginOnly, 5, 25), .init(.atLeast, 30, 30),
                .init(.percent, 100, 20),
            ]
            for row in tall {
                let string = Self.objectLine(marker: 40, objectHeight: 20, rule: row.rule)
                let frame = Self.measure(string, rule: row.rule)
                expect(frame.lines.map(\.boxHeight)).to(equal([20]), description: row.label)
                expect(Double(frame.totalHeight))
                    .to(beCloseTo(Double(row.expected), within: 0.001), description: row.label)
            }
            let atLeast = Fixtures.rule(.atLeast, 12)
            let small = Self.objectLine(marker: 40, objectHeight: 8, rule: atLeast)
            let frame = Self.measure(small, rule: atLeast)
            expect(frame.lines.map(\.boxHeight)) == [10]
            expect(Double(frame.totalHeight)).to(beCloseTo(12, within: 0.001))
        }

        // MARK: 개체만 있는 줄

        /// 개체만 남은 가운데 줄은 개체 높이가 상자다 — 마커가 40pt든 10pt든 한글 캐시 800/680이고
        /// 여분만 마커 기준(2400·600)이다 (N1·N2: 'N1 ' + 폭 60pt·높이 8pt 그림 16개 + ' 뒤'가
        /// 425.2pt 단에서 6·7·3개로 나뉜다). 종전에는 마커 크기(40·10)가 상자였다.
        func testObjectOnlyMiddleLineTakesTheObjectHeight() {
            for (marker, share) in [(CGFloat(40), CGFloat(24)), (10, 6)] {
                let text = Fixtures.attributes(size: 10)
                let output = NSMutableAttributedString(string: "N1 ", attributes: text)
                for _ in 0 ..< 16 {
                    output.append(Self.marker(
                        height: 8, width: 60, attributes: Fixtures.attributes(size: marker)
                    ))
                }
                output.append(NSAttributedString(string: " 뒤", attributes: text))
                let string = Fixtures.applying(Self.percent160, to: output)
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: CGPoint(x: 0, y: Fixtures.blockTop),
                    lineWidth: 425.2
                )
                let boxes = lines.map {
                    HwpDrawnTextLayout.lineMetrics(of: $0.line, in: string).boxHeight
                }
                expect(boxes).to(equal([10, 8, 10]), description: "마커 \(marker)pt")
                expect(lines.map { Double($0.baselineOrigin.y) }).to(beCloseTo(
                    Fixtures.expectedBaselines(
                        boxes: [10, 8, 10], advances: [10 + share, 8 + share, 10 + share]
                    ),
                    within: 0.001
                ), description: "마커 \(marker)pt")
            }
        }

        /// 개체만 있는 문단의 마지막 줄에는 문단 끝 글자(CR)의 크기가 든다 — 40pt 마커의 8pt
        /// 그림만 있는 문단은 CR이 10pt면 1000/850/2400(O1), 40pt면 4000/3400/2400(O2). CR
        /// 표식이 없는 문자열(공개 `drawText` 호출자)은 개체 높이가 상자다.
        func testParagraphEndSizeStillJoinsAnObjectOnlyParagraph() {
            let bare = Fixtures.applying(
                Self.percent160,
                to: Self.marker(height: 8, attributes: Fixtures.attributes(size: 40))
            )
            for (endSize, box) in [(CGFloat(10), CGFloat(10)), (40, 40)] {
                let string = Self.withEndSize(endSize, bare)
                expect(Self.metrics(of: string).boxHeight)
                    .to(equal(box), description: "CR \(endSize)pt")
                expect(Double(Self.measure(string, rule: Self.percent160).totalHeight))
                    .to(beCloseTo(Double(box + 24), within: 0.001), description: "CR \(endSize)pt")
            }
            expect(Self.metrics(of: bare).boxHeight) == 8
            expect(Double(Self.measure(bare, rule: Self.percent160).totalHeight))
                .to(beCloseTo(8 + 24, within: 0.001))
        }

        // MARK: 줄 공간을 예약하지 않은 마커

        /// 높이 0 마커(책갈피)의 글자 모양은 종전대로 상자에 든다 — 10pt 글 + 40pt 책갈피(K1)
        /// 4000/3400/2400, 책갈피만 있는 줄(K5 — 문단 끝 10pt여도) 4000, 8pt 그림과 한 줄에 있어도
        /// (40pt 마커 그림 + 40pt 책갈피) 4000. 판정은 폭이 아니라 예약 높이다 — 폭 있는 높이 0
        /// 마커도 같다.
        func testHeightZeroMarkerStillJoinsTheLineBox() {
            let text = Fixtures.attributes(size: 10)
            let bookmark = Self.marker(
                height: 0, width: 0, attributes: Fixtures.attributes(size: 40)
            )
            let bookmarkLine = NSMutableAttributedString(string: "ab", attributes: text)
            bookmarkLine.append(bookmark)
            bookmarkLine.append(NSAttributedString(string: "cd", attributes: text))
            let withText = Fixtures.applying(Self.percent160, to: bookmarkLine)
            expect(Self.metrics(of: withText).boxHeight) == 40
            expect(Self.metrics(of: withText).objectMarkerBaseFontSize) == 0
            expect(Fixtures.baselines(withText))
                .to(beCloseTo([Double(Fixtures.blockTop + 34)], within: 0.001))
            expect(Double(Self.measure(withText, rule: Self.percent160).totalHeight))
                .to(beCloseTo(64, within: 0.001))

            let alone = Self.withEndSize(10, Fixtures.applying(Self.percent160, to: bookmark))
            expect(Self.metrics(of: alone).boxHeight) == 40

            let mixed = NSMutableAttributedString(string: "ab", attributes: text)
            mixed.append(Self.marker(height: 8, attributes: Fixtures.attributes(size: 40)))
            mixed.append(bookmark)
            expect(Self.metrics(of: Fixtures.applying(Self.percent160, to: mixed)).boxHeight) == 40

            let wide = Self.marker(height: 0, width: 20, attributes: Fixtures.attributes(size: 40))
            let wideLine = NSMutableAttributedString(string: "ab", attributes: text)
            wideLine.append(wide)
            expect(Self.metrics(of: wideLine).boxHeight) == 40
        }

        // MARK: 줄 단위 밑줄

        /// 밑줄 기준(#226)은 마커의 글자 모양과 무관하다 — 한글 12.30 PDF (2026-09-24): 10pt 밑줄
        /// 글 + 20pt 그림 줄의 밑줄 중심이 마커 10pt·40pt 모두 베이스라인 아래 3.24, 40pt 그림은
        /// 6.12·6.24 (상자 바닥 0.15 × 개체 + 10pt 두께 절반), 두께는 전부 0.36pt. 개체 마커의
        /// 글자 모양은 줄 상자에도(#217) 두께 기준에도 들지 않는다.
        func testUnderlineReferenceIgnoresTheMarkerSize() {
            let reference = { (string: NSAttributedString) in
                HwpDrawnTextLayout.underlineReference(
                    of: CTLineCreateWithAttributedString(string), endsParagraph: false
                )
            }
            for object in [CGFloat(20), 40] {
                let small = reference(Self.objectLine(marker: 10, objectHeight: object))
                let large = reference(Self.objectLine(marker: 40, objectHeight: object))
                expect(large).to(equal(small), description: "개체 \(object)pt")
                expect(large.lineBoxHeight).to(beCloseTo(object, within: 0.0001))
                expect(large.textFontSize).to(beCloseTo(10, within: 0.0001))
            }
            // 글자가 상자를 정한 8pt 그림 줄은 글자 줄 자리다 (한글: 밑줄 1.68 — 글자 줄과 같다).
            let short = reference(Self.objectLine(marker: 40, objectHeight: 8))
            expect(short.lineBoxHeight).to(beCloseTo(10, within: 0.0001))
            expect(short.textFontSize).to(beCloseTo(10, within: 0.0001))
        }

        // MARK: MS 워드 호환 문서

        /// MS 워드 호환 문서는 바뀌지 않는다 — 마커 글꼴은 원래 줄 상자에서 빠지고(#194) 새 값은
        /// 한글 문서 경로만 읽는다. 10pt 글 + 40pt 마커의 4pt 그림(글꼴 베이스라인보다 낮다) 줄
        /// 상자는 글자 줄과 같고, 여분 기준만 마커의 40pt다 (`msWordSpacingBase`).
        func testMsWordDocumentsKeepTheirFontLineBox() {
            let msWord = NSNumber(value: HwpCompatibleDocumentTarget.msWord.rawValue)
            var text = Fixtures.attributes(size: 10)
            text[HwpAttributedStringKey.compatibleDocumentTarget] = msWord
            var marker = Fixtures.attributes(size: 40)
            marker[HwpAttributedStringKey.compatibleDocumentTarget] = msWord
            let textOnly = NSAttributedString(string: "ab", attributes: text)
            let withObject = NSMutableAttributedString(attributedString: textOnly)
            withObject.append(Self.marker(height: 4, attributes: marker))
            let plain = Self.metrics(of: Fixtures.applying(Self.percent160, to: textOnly))
            let object = Self.metrics(of: Fixtures.applying(Self.percent160, to: withObject))
            expect(object.boxHeight).to(beCloseTo(plain.boxHeight, within: 0.0001))
            expect(object.baselineAnchor).to(beCloseTo(plain.baselineAnchor, within: 0.0001))
            expect(object.textBoxHeight) == 40
        }

        // MARK: 헬퍼

        /// 한 줄 표본 — 마커 글자 모양 크기·개체 높이와 한글 캐시의 상자·160% 여분 (pt).
        private struct MarkerRow {
            let marker: CGFloat
            let object: CGFloat
            let box: CGFloat
            let share: CGFloat
        }

        /// 개체 마커 — 높이 `height`(0이면 줄 공간을 예약하지 않는 마커)·폭 `width`의 run delegate를
        /// 단 U+FFFC. 글자 모양(`attributes`)을 싣고, 예약한 마커에는 빌더처럼 예약 높이 표식
        /// (`hwp.inlineObjectHeight`)도 단다 (`HwpTextRunBuilder.appendControlMarker`).
        static func marker(
            height: CGFloat, width: CGFloat = 40, attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            var marker = attributes
            if let delegate = HwpInlineObjectReservation.runDelegate(width: width, height: height) {
                marker[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
            }
            if height > 0 {
                marker[HwpAttributedStringKey.inlineObjectHeight] = NSNumber(value: Double(height))
            }
            marker[HwpAttributedStringKey.controlIndex] = NSNumber(value: 0)
            return NSAttributedString(string: "\u{FFFC}", attributes: marker)
        }

        /// `ab▯cd` — 10pt 글 사이에 글자 모양 `marker`pt인 마커로 `objectHeight`pt 개체를 실은 한 줄.
        private static func objectLine(
            marker: CGFloat, objectHeight: CGFloat, rule: HwpLineSpacingRule = percent160
        ) -> NSAttributedString {
            let text = Fixtures.attributes(size: 10)
            let output = NSMutableAttributedString(string: "ab", attributes: text)
            output.append(
                Self.marker(height: objectHeight, attributes: Fixtures.attributes(size: marker))
            )
            output.append(NSAttributedString(string: "cd", attributes: text))
            return Fixtures.applying(rule, to: output)
        }

        /// 한 줄 문자열의 줄 지표 (문단 문자열로 판정 — 마지막 줄이면 CR 크기가 든다).
        static func metrics(
            of string: NSAttributedString
        ) -> HwpDrawnTextLayout.LineMetrics {
            HwpDrawnTextLayout.lineMetrics(
                of: CTLineCreateWithAttributedString(string), in: string
            )
        }

        /// 문자열 전체에 CR 기본 크기를 싣는다 (`attachParagraphEndBaseFontSize`와 같은 꼴).
        static func withEndSize(
            _ size: CGFloat, _ string: NSAttributedString
        ) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: string)
            output.addAttribute(
                HwpAttributedStringKey.paragraphEndBaseFontSize,
                value: NSNumber(value: Double(size)),
                range: NSRange(location: 0, length: output.length)
            )
            return output
        }

        /// 측정 — `rule`의 문단 모양(문단 간격 0)을 `attachParagraphStyle`로 달아 잰다.
        static func measure(
            _ string: NSAttributedString, rule: HwpLineSpacingRule
        ) -> HwpParagraphFrame {
            let shape = Fixtures.paraShape(rule: rule)
            let styled = NSMutableAttributedString(attributedString: string)
            HwpParagraphLayout.attachParagraphStyle(to: styled, paraShape: shape)
            return HwpParagraphLayout().layout(
                attributedString: styled, paraShape: shape, columnWidth: Fixtures.wideWidth
            )
        }
    }
#endif
