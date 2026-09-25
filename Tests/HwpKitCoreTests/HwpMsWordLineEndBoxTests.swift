import CoreGraphics
import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// MS 워드 호환 문서에서 **줄 끝 글자**(문단 끝 CR·한 줄 끝 LF)와 글자처럼 취급 개체가 줄
    /// 상자에 드는 규칙 (#223) — 글자 run 상자들의 축별 최댓값 T에 끝 글자 상자 C와 개체 높이
    /// O를 **쌓는다**: 높이 = T 높이, 다만 C가 T보다 높으면 C 높이 + T의 베이스라인 아래 몫, O가
    /// T보다 높으면 O + T의 아래 몫과 견줘 큰 것. 베이스라인 = max(T, C, O). 비율 여분은
    /// max(T, C) 기준이고, 밑줄은 줄 상자 가장자리에서 **T의** cell × 0.129만큼 안쪽이다 (T가
    /// 없으면 C의 cell, 개체만 있는 줄은 개체 마커 글꼴의 cell).
    ///
    /// 오라클은 한글 12.30.0 (build 6446, 2026-09-25)이 `targetProgram="MS_WORD"` 합성 HWPX
    /// (줄 캐시 없음)를 다시 저장한 줄 캐시(`vertsize`·`textheight`·`baseline`·`spacing`)와 PDF
    /// 밑줄 벡터다. 기대값은 같은 글꼴의 OS/2 지표에서 `HwpMsWordLineBox`로 계산하고, 한글
    /// 캐시와는 글꼴 상자 반올림(±0.03pt) 안에서 만난다.
    ///
    /// | 줄 | 한글 `vertsize`/`baseline` | 산식 |
    /// |---|---:|---|
    /// | Apple SD 10 + Menlo 빈칸 글 + Menlo 16 끝 글자 | 2879/1766 | 24.21 + 4.57 |
    /// | Menlo 10 글 + Apple SD 10 끝 글자 | 1970/1104 | 15.60 + 4.10 |
    /// | Apple SD 20 글 + Menlo 20 끝 글자 | 3119/2207 | 축별 최댓값 (C가 낮다) |
    /// | 10pt 글 + 20pt 한 줄 끝 (줄 `textheight`) | 3809 | 33.84 + 4.26 (함초롬돋움) |
    /// | 한 줄 끝 뒤 빈 줄 (10pt LF + 16pt CR / 16pt LF + 10pt CR) | 2706 / 1692 | C만 |
    /// | Apple SD 20 글 + 25pt 표 + Menlo 20 끝 글자 | 3119/2500 | O ≤ T 높이 → 베이스라인만 |
    /// | 10pt 글 + 26pt 표 + 16pt 끝 글자 (함초롬돋움) | 3132/2600 | max(27.06, 26) + 4.26 |
    /// | 표만 + 10pt 끝 글자 | 3000/3000 | T 없음 → max(C, O) |
    /// | 자동 줄바꿈으로 나뉜 표만 있는 앞 줄 (10pt 마커 30pt 표, 160%) | 3000/3000, `spacing` 600 | T·C 없음 → O, 여분은 마커 크기 |
    final class HwpMsWordLineEndBoxTests: XCTestCase {
        private typealias Key = NSAttributedString.Key
        private static let blockTop: CGFloat = 100

        private static func font(_ name: String, _ size: CGFloat) -> CTFont {
            CTFontCreateWithName(name as CFString, size, nil)
        }

        private static func box(_ name: String, _ size: CGFloat) -> HwpMsWordLineBox {
            HwpMsWordLineBox.metrics(of: font(name, size)).scaled(by: size)
        }

        private static func attributes(_ name: String, _ size: CGFloat) -> [Key: Any] {
            [
                kCTFontAttributeName as Key: font(name, size),
                HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(size)),
                HwpAttributedStringKey.compatibleDocumentTarget: NSNumber(
                    value: HwpCompatibleDocumentTarget.msWord.rawValue
                ),
            ]
        }

        private static func text(_ string: String, _ name: String, _ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: string, attributes: attributes(name, size))
        }

        /// 문단 끝 상자(`hwp.msWordParagraphEndBox`)와 비율 160%를 문자열 전체에 단다.
        private static func finish(
            _ parts: [NSAttributedString], endBox: HwpMsWordLineBox? = nil
        ) -> NSAttributedString {
            let string = NSMutableAttributedString()
            parts.forEach(string.append)
            let range = NSRange(location: 0, length: string.length)
            if let endBox {
                string.addAttribute(
                    HwpAttributedStringKey.msWordParagraphEndBox,
                    value: [
                        NSNumber(value: Double(endBox.lineHeight)),
                        NSNumber(value: Double(endBox.baseline)),
                    ],
                    range: range
                )
            }
            string.addAttribute(
                HwpAttributedStringKey.lineSpacing,
                value: HwpLineSpacingRule(kind: .percent, value: 160).attributeValue, range: range
            )
            return string
        }

        private static func lines(_ string: NSAttributedString, width: CGFloat = 400) -> [HwpDrawnLine] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: blockTop), lineWidth: width
            )
        }

        private static func metrics(
            _ string: NSAttributedString, line index: Int = 0
        ) throws -> HwpDrawnTextLayout.LineMetrics {
            let drawn = lines(string)
            let line = try XCTUnwrap(drawn.indices.contains(index) ? drawn[index] : nil, "줄 \(index)")
            return HwpDrawnTextLayout.lineMetrics(of: line.line, in: string)
        }

        private func skipUnlessOracleFonts() throws {
            try XCTSkipUnless(
                Self.box("Apple SD Gothic Neo", 10).cellHeight > 11.5
                    && Self.box("Menlo", 10).cellHeight > 11.5,
                "Apple SD 산돌고딕 Neo·Menlo 없음"
            )
        }

        /// 끝 글자 상자가 글자 상자보다 높으면 그 위에 **글자 상자의 아래 몫**이 붙는다 — Apple SD
        /// 10pt 한글과 Menlo 빈칸의 줄(T = 15.60/11.03)에 Menlo 16pt 끝 글자(24.21/17.65)면
        /// 28.78/17.65 (한글 2879/1766), 160% 여분은 끝 상자 기준 14.56 (한글 1456). 끝 상자가
        /// 낮으면(Menlo 10pt) 종전 축별 최댓값 그대로다.
        func testTallerParagraphEndBoxStacksOnTheTextBelowShare() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo10 = Self.box("Menlo", 10)
            let menlo16 = Self.box("Menlo", 16)
            func paragraph(end: HwpMsWordLineBox) -> NSAttributedString {
                Self.finish([
                    Self.text("가나", "Apple SD Gothic Neo", 10), Self.text(" ", "Menlo", 10),
                    Self.text("다", "Apple SD Gothic Neo", 10),
                ], endBox: end)
            }
            let textBelow = appleSD.lineHeight - menlo10.baseline
            let stacked = try Self.metrics(paragraph(end: menlo16))
            expect(stacked.boxHeight).to(beCloseTo(menlo16.lineHeight + textBelow, within: 0.001))
            expect(stacked.baselineAnchor).to(beCloseTo(menlo16.baseline, within: 0.001))
            expect(stacked.textBoxHeight).to(beCloseTo(menlo16.lineHeight, within: 0.001))
            expect(stacked.boxHeight).to(beCloseTo(28.79, within: 0.03))
            let stackedString = paragraph(end: menlo16)
            let stackedLine = try XCTUnwrap(Self.lines(stackedString).first)
            let advance = HwpLineAdvance.lineAdvance(of: stackedLine.line, at: 0, in: stackedString)
            expect(advance).to(beCloseTo(
                stacked.boxHeight + HwpLineSpacingRule.percentShare(of: menlo16.lineHeight, percent: 160),
                within: 0.001
            ))
            // 한글은 Menlo 16pt 상자를 24.24로 반올림해 여분이 1456이다 (우리 24.21 → 1452 — 글꼴
            // 상자 반올림의 알려진 격차, `HwpMsWordLineBox` #194 "남은 격차").
            expect(HwpLineSpacingRule.percentShare(of: menlo16.lineHeight, percent: 160))
                .to(beCloseTo(14.56, within: 0.05))
            let joined = try Self.metrics(paragraph(end: menlo10))
            expect(joined.boxHeight).to(beCloseTo(appleSD.lineHeight, within: 0.001))
            expect(joined.baselineAnchor).to(beCloseTo(menlo10.baseline, within: 0.001))
        }

        /// 쌓을지는 글자 크기나 베이스라인이 아니라 **상자 높이**가 가른다 — 같은 10pt라도 Menlo
        /// 글(15.13)에 Apple SD 끝 글자(15.60, 베이스라인은 더 얕은 10.80)면 쌓여 19.70/11.03
        /// (한글 1970/1104), Apple SD 20pt 글(31.20)에 Menlo 20pt 끝 글자(30.27, 베이스라인은 더
        /// 깊은 22.06)면 축별 최댓값 31.20/22.06 (한글 3119/2207). 같은 글꼴·크기면 두 상자가
        /// 정확히 같아 쌓이지 않는다.
        func testStackingFollowsTheBoxHeightNotTheSizeOrBaseline() throws {
            try skipUnlessOracleFonts()
            let menlo10 = Self.box("Menlo", 10)
            let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
            let shallow = try Self.metrics(Self.finish(
                [Self.text("menlo", "Menlo", 10)], endBox: appleSD10
            ))
            expect(shallow.boxHeight).to(beCloseTo(
                appleSD10.lineHeight + menlo10.lineHeight - menlo10.baseline, within: 0.001
            ))
            expect(shallow.baselineAnchor).to(beCloseTo(menlo10.baseline, within: 0.001))
            expect(shallow.boxHeight).to(beCloseTo(19.70, within: 0.03))
            let menlo20 = Self.box("Menlo", 20)
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let deeper = try Self.metrics(Self.finish(
                [Self.text("가나다", "Apple SD Gothic Neo", 20)], endBox: menlo20
            ))
            expect(deeper.boxHeight).to(beCloseTo(appleSD20.lineHeight, within: 0.001))
            expect(deeper.baselineAnchor).to(beCloseTo(menlo20.baseline, within: 0.001))
            let equal = try Self.metrics(Self.finish([Self.text("menlo", "Menlo", 10)], endBox: menlo10))
            expect(equal.boxHeight) == menlo10.lineHeight
            expect(equal.baselineAnchor) == menlo10.baseline
        }

        /// 쌓이는 아래 몫은 **합친 글자 상자**의 것이다 — Apple SD 20pt 한글 + Menlo 20pt 라틴 줄
        /// (T = 31.20/22.06, 아래 몫 9.14)에 30pt 끝 글자면 끝 상자 + 9.14이지 Apple SD 혼자의 아래
        /// 몫 9.60이 아니다 (한글 실측: 함초롬돋움 30pt 끝 글자 5986 = 끝 상자 5074 + 912).
        func testStackedBelowShareIsTheUnionTextBoxShare() throws {
            try skipUnlessOracleFonts()
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let menlo20 = Self.box("Menlo", 20)
            let end = Self.box("Apple SD Gothic Neo", 30)
            let metrics = try Self.metrics(Self.finish([
                Self.text("가나다", "Apple SD Gothic Neo", 20), Self.text("abc", "Menlo", 20),
            ], endBox: end))
            let unionBelow = appleSD20.lineHeight - menlo20.baseline
            expect(metrics.boxHeight).to(beCloseTo(end.lineHeight + unionBelow, within: 0.001))
            expect(unionBelow).toNot(beCloseTo(appleSD20.lineHeight - appleSD20.baseline, within: 0.1))
            expect(metrics.baselineAnchor).to(beCloseTo(end.baseline, within: 0.001))
        }

        /// 한 줄 끝(LF)도 문단 끝 글자처럼 쌓인다 — Apple SD 10pt 글 뒤의 Menlo 16pt 한 줄 끝 줄은
        /// 24.21 + 4.80 (한글 실측: 함초롬돋움 10pt 글 + 20pt 한 줄 끝 `textheight` 3809 = 3384 +
        /// 426, 16pt 3132), 비율 여분도 한 줄 끝 상자 기준이다. 같은 크기의 한 줄 끝은 쌓이지 않고,
        /// 다음 줄(문단 끝)은 자기 글자와 끝 상자로 따로 잰다.
        func testLineBreakStacksLikeTheParagraphEnd() throws {
            try skipUnlessOracleFonts()
            let appleSD = Self.box("Apple SD Gothic Neo", 10)
            let menlo16 = Self.box("Menlo", 16)
            func paragraph(breakSize: CGFloat) -> NSAttributedString {
                Self.finish([
                    Self.text("가나", "Apple SD Gothic Neo", 10),
                    LineBoxFixtures.lineBreak(attributes: Self.attributes("Menlo", breakSize)),
                    Self.text("뒤", "Apple SD Gothic Neo", 10),
                ], endBox: Self.box("Menlo", 10))
            }
            let stacked = try Self.metrics(paragraph(breakSize: 16))
            expect(stacked.boxHeight).to(beCloseTo(
                menlo16.lineHeight + appleSD.lineHeight - appleSD.baseline, within: 0.001
            ))
            expect(stacked.baselineAnchor).to(beCloseTo(menlo16.baseline, within: 0.001))
            expect(stacked.textBoxHeight).to(beCloseTo(menlo16.lineHeight, within: 0.001))
            let second = try Self.metrics(paragraph(breakSize: 16), line: 1)
            expect(second.boxHeight).to(beCloseTo(appleSD.lineHeight, within: 0.001))
            let plain = try Self.metrics(paragraph(breakSize: 10))
            expect(plain.boxHeight).to(beCloseTo(appleSD.lineHeight, within: 0.001))
        }

        /// 한 줄 끝 뒤의 빈 마지막 줄은 **문단 끝 상자뿐**이다 — 빈 줄 앵커는 조판 문자열에만 있는
        /// 글자라 글자 상자에 들지 않는다 (한글 실측: 10pt 한 줄 끝 + 16pt 끝 글자의 빈 줄
        /// 2706/2025, 16pt 한 줄 끝 + 10pt 끝 글자는 1692/1266 — 한 줄 끝 크기가 아니다).
        func testEmptyLastLineAfterALineBreakIsTheParagraphEndBoxAlone() throws {
            try skipUnlessOracleFonts()
            func lastLine(anchorSize: CGFloat, end: HwpMsWordLineBox) throws -> HwpDrawnTextLayout.LineMetrics {
                let string = Self.finish([
                    Self.text("가나", "Apple SD Gothic Neo", 10),
                    LineBoxFixtures.lineBreak(attributes: Self.attributes("Menlo", anchorSize)),
                    LineBoxFixtures.emptyLineAnchor(attributes: Self.attributes("Menlo", anchorSize)),
                ], endBox: end)
                return try Self.metrics(string, line: 1)
            }
            let menlo16 = Self.box("Menlo", 16)
            let tall = try lastLine(anchorSize: 10, end: menlo16)
            expect(tall.boxHeight).to(beCloseTo(menlo16.lineHeight, within: 0.001))
            expect(tall.baselineAnchor).to(beCloseTo(menlo16.baseline, within: 0.001))
            let menlo10 = Self.box("Menlo", 10)
            let short = try lastLine(anchorSize: 16, end: menlo10)
            expect(short.boxHeight).to(beCloseTo(menlo10.lineHeight, within: 0.001))
            expect(short.baselineAnchor).to(beCloseTo(menlo10.baseline, within: 0.001))
        }

        /// 개체는 **글자 상자보다 높을 때만** 쌓인다 — Apple SD 20pt 글(31.20/21.60)의 25pt 표는
        /// 베이스라인만 25로 내리고 상자는 31.20 그대로 (한글 3119/2500; 종전 산식 34.12), 40pt
        /// 표는 40 + 9.60. 끝 글자와 함께면 둘을 따로 재어 큰 쪽이다 (10pt 글 + 26pt 표 + 16pt 끝
        /// 글자: max(끝 상자 + 아래 몫, 26 + 아래 몫)).
        func testObjectsStackOnlyWhenTallerThanTheTextBox() throws {
            try skipUnlessOracleFonts()
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let text20 = Self.attributes("Apple SD Gothic Neo", 20)
            func objectLine(_ height: CGFloat) throws -> HwpDrawnTextLayout.LineMetrics {
                try Self.metrics(Self.finish([
                    Self.text("가나", "Apple SD Gothic Neo", 20),
                    LineBoxFixtures.objectMarker(height: height, attributes: text20),
                ], endBox: Self.box("Menlo", 20)))
            }
            let band = try objectLine(25)
            expect(band.boxHeight).to(beCloseTo(appleSD20.lineHeight, within: 0.001))
            expect(band.baselineAnchor).to(beCloseTo(25, within: 0.001))
            let tall = try objectLine(40)
            expect(tall.boxHeight).to(beCloseTo(
                40 + appleSD20.lineHeight - appleSD20.baseline, within: 0.001
            ))
            expect(tall.baselineAnchor).to(beCloseTo(40, within: 0.001))
            let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
            let menlo16 = Self.box("Menlo", 16)
            let below10 = appleSD10.lineHeight - appleSD10.baseline
            for (height, expected) in [
                (CGFloat(22), menlo16.lineHeight + below10), (30, 30 + below10),
            ] {
                let metrics = try Self.metrics(Self.finish([
                    Self.text("가나", "Apple SD Gothic Neo", 10),
                    LineBoxFixtures.objectMarker(
                        height: height, attributes: Self.attributes("Apple SD Gothic Neo", 10)
                    ),
                ], endBox: menlo16))
                expect(metrics.boxHeight).to(beCloseTo(expected, within: 0.001), description: "\(height)")
                expect(metrics.baselineAnchor).to(beCloseTo(height, within: 0.001), description: "\(height)")
                expect(metrics.textBoxHeight).to(beCloseTo(menlo16.lineHeight, within: 0.001))
            }
        }

        /// 글자 없이 개체와 문단 끝 글자만 있는 줄은 max(끝 상자, 개체)다 — 아래 몫을 붙일 글자
        /// 상자가 없다 (한글 실측: 30pt 표 + 10pt 끝 글자 3000/3000, 40pt 끝 글자 6766/5063).
        /// 개체가 상자 높이와 같아져도 MS 워드 호환 줄의 밑줄은 그 글꼴 줄 상자에서 잰다.
        func testObjectOnlyParagraphLineIsTheLargerOfTheEndBoxAndTheObject() throws {
            try skipUnlessOracleFonts()
            let marker = Self.attributes("Apple SD Gothic Neo", 10)
            func objectOnly(end: HwpMsWordLineBox) -> NSAttributedString {
                Self.finish([LineBoxFixtures.objectMarker(height: 30, attributes: marker)], endBox: end)
            }
            let small = try Self.metrics(objectOnly(end: Self.box("Menlo", 10)))
            expect(small.boxHeight).to(beCloseTo(30, within: 0.001))
            expect(small.baselineAnchor).to(beCloseTo(30, within: 0.001))
            let line = try XCTUnwrap(Self.lines(objectOnly(end: Self.box("Menlo", 10))).first)
            // 밑줄은 한글 문서의 줄 상자 바닥 규칙이 아니라 MS 워드 줄 상자에서 잰다 (#226).
            expect(HwpDrawnTextLayout.underlineReference(of: line.line, endsParagraph: true)
                .msWordLineBox)
                == HwpDrawnTextLayout.msWordLineBox(of: line.line, endsParagraph: true)
            let menlo40 = Self.box("Menlo", 40)
            let large = try Self.metrics(objectOnly(end: menlo40))
            expect(large.boxHeight).to(beCloseTo(menlo40.lineHeight, within: 0.001))
            expect(large.baselineAnchor).to(beCloseTo(menlo40.baseline, within: 0.001))
        }

        /// 글자도 줄 끝 글자도 없이 **개체만 있는 줄**(자동 줄바꿈으로 나뉜 앞 줄)도 상자 = 개체다
        /// — 개체 마커의 글꼴은 글자 상자로 떨어지지 않고, 비율 여분은 마커 기본 크기 기준이다
        /// (#223 PR 리뷰, 한글 12.30 실측 2026-09-25: 넓은 30pt 표 둘을 한 줄에 하나씩 놓은
        /// 문단의 앞 줄 3000/3000·160% `spacing` 600 — 마지막 줄 3000/3000과 같은 규칙, 16pt
        /// 마커면 960, Apple SD/Menlo 마커도 같다). 마커 글꼴을 글자 상자로 삼으면 앞 줄만
        /// 30 + 마커 글꼴의 아래 몫이 되어 한 문단 안에서 규칙이 갈린다 (함초롬돋움 10pt 마커:
        /// 34.26 — 다시 조판한 뒤 문단이 한글 PDF보다 앞 줄마다 8.3pt 안팎씩 아래에 놓였다). 줄
        /// 공간을 예약하지 않은 마커만 있는 줄은 종전대로(#194) 그 마커의 글꼴로 떨어진다.
        func testWrappedObjectOnlyLineIsTheObject() throws {
            try skipUnlessOracleFonts()
            let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
            func gallery(markerSize: CGFloat) -> NSAttributedString {
                let marker = Self.attributes("Apple SD Gothic Neo", markerSize)
                return Self.finish([
                    LineBoxFixtures.objectMarker(height: 30, attributes: marker),
                    LineBoxFixtures.objectMarker(height: 30, attributes: marker),
                ], endBox: Self.box("Menlo", 10))
            }
            for (markerSize, share) in [(CGFloat(10), CGFloat(6)), (16, 9.6)] {
                let string = gallery(markerSize: markerSize)
                let drawn = Self.lines(string, width: 30)
                expect(drawn.count) == 2
                guard drawn.count == 2 else { return }
                expect(drawn[0].endsParagraph).to(beFalse())
                let wrapped = HwpDrawnTextLayout.lineMetrics(of: drawn[0].line, in: string)
                expect(wrapped.boxHeight).to(beCloseTo(30, within: 0.001), description: "\(markerSize)")
                expect(wrapped.baselineAnchor).to(beCloseTo(30, within: 0.001), description: "\(markerSize)")
                expect(wrapped.textBoxHeight).to(beCloseTo(markerSize, within: 0.001))
                expect(wrapped.inlineObjectBaselineRatio) == 1
                let last = HwpDrawnTextLayout.lineMetrics(of: drawn[1].line, in: string)
                expect(last.boxHeight).to(beCloseTo(30, within: 0.001), description: "\(markerSize)")
                // 다음 줄은 앞 줄 상자 30 + 마커 기본 크기 기준 여분 아래다 (한글 3000 + 600·960).
                expect(drawn[1].baselineOrigin.y - drawn[0].baselineOrigin.y)
                    .to(beCloseTo(30 + share, within: 0.001), description: "\(markerSize)")
            }
            // 장식선 기준 상자는 마커 글꼴의 cell이고, 밑줄 기준은 그 줄 상자다.
            let string = gallery(markerSize: 10)
            let first = try XCTUnwrap(Self.lines(string, width: 30).first)
            let box = try XCTUnwrap(HwpDrawnTextLayout.msWordLineBox(of: first.line, endsParagraph: false))
            expect(box.lineHeight).to(beCloseTo(30, within: 0.001))
            expect(box.cellHeight).to(beCloseTo(appleSD10.cellHeight, within: 0.001))
            expect(HwpDrawnTextLayout.underlineReference(of: first.line, endsParagraph: false)
                .msWordLineBox) == box
            // 줄 공간을 예약하지 않은 마커(높이 0 — 책갈피·자리 차지 개체 앵커)만 있는 줄은 그
            // 마커의 글꼴 상자다 — 상자가 0이 되지 않는다.
            let menlo16 = Self.box("Menlo", 16)
            let anchors = Self.finish([
                LineBoxFixtures.objectMarker(height: 0, attributes: Self.attributes("Menlo", 16)),
                LineBoxFixtures.objectMarker(height: 0, attributes: Self.attributes("Menlo", 16)),
            ], endBox: Self.box("Menlo", 10))
            let anchorLine = try XCTUnwrap(Self.lines(anchors, width: 30).first)
            let anchorMetrics = HwpDrawnTextLayout.lineMetrics(of: anchorLine.line, in: anchors)
            expect(anchorMetrics.boxHeight).to(beCloseTo(menlo16.lineHeight, within: 0.001))
            expect(anchorMetrics.baselineAnchor).to(beCloseTo(menlo16.baseline, within: 0.001))
        }

        /// 개체가 있는 줄에서는 폭·높이 0인 마커(구역 첫 문단의 구역·단 정의, 책갈피, 필드 표식)의
        /// 글꼴도 글자 상자가 되지 않는다 — 한글 12.30 실측 (2026-09-25 `mk223`, #223 PR 리뷰):
        /// 자동 줄바꿈으로 30pt 표만 남은 앞 줄에 구역·단 정의나 10·16pt 책갈피가 함께 있어도
        /// 3000/3000·160% `spacing` 600이다 (16pt 책갈피의 크기도 여분에 들지 않는다). 그 마커를
        /// 글자 상자로 삼으면 30 + 그 글꼴의 아래 몫이 된다. 글자가 있는 개체 줄의 장식선 cell은
        /// 개체 마커가 다른 글꼴이어도 글자 상자의 것이다.
        func testAnchorMarkersDoNotSizeAnObjectLine() throws {
            try skipUnlessOracleFonts()
            let marker = Self.attributes("Apple SD Gothic Neo", 10)
            var anchorAttributes = Self.attributes("Menlo", 16)
            anchorAttributes[kCTRunDelegateAttributeName as Key] =
                HwpInlineObjectReservation.runDelegate(width: 0, height: 0)
            let string = Self.finish([
                NSAttributedString(string: "\u{FFFC}", attributes: anchorAttributes),
                LineBoxFixtures.objectMarker(height: 30, attributes: marker),
                LineBoxFixtures.objectMarker(height: 30, attributes: marker),
            ], endBox: Self.box("Menlo", 10))
            let drawn = Self.lines(string, width: 30)
            expect(drawn.count) == 2
            let first = try XCTUnwrap(drawn.first)
            expect(first.endsParagraph).to(beFalse())
            let metrics = HwpDrawnTextLayout.lineMetrics(of: first.line, in: string)
            expect(metrics.boxHeight).to(beCloseTo(30, within: 0.001))
            expect(metrics.baselineAnchor).to(beCloseTo(30, within: 0.001))
            expect(metrics.textBoxHeight).to(beCloseTo(10, within: 0.001))
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let band = Self.finish([
                Self.text("가나", "Apple SD Gothic Neo", 20),
                LineBoxFixtures.objectMarker(height: 30, attributes: Self.attributes("Menlo", 16)),
            ], endBox: Self.box("Menlo", 20))
            let bandLine = try XCTUnwrap(Self.lines(band).first)
            let bandBox = try XCTUnwrap(
                HwpDrawnTextLayout.msWordLineBox(of: bandLine.line, endsParagraph: true)
            )
            expect(bandBox.cellHeight) == appleSD20.cellHeight
            expect(bandBox.cellHeight) != Self.box("Menlo", 16).cellHeight
        }

        /// 결합 문자열(각주·글상자 블록이 문단들을 `\n`으로 이은 것)의 문단 구분자는 앞 문단의
        /// 끝 글자 자리라 글자 상자에 들지 않는다 — 개체로 끝나는 문단의 줄이 홀로 잴 때(30)와
        /// 같아야 한다. 구분자를 글자로 세면 30 + 구분자 글꼴의 아래 몫이 된다.
        func testCombinedSeparatorDoesNotJoinTheTextBox() throws {
            try skipUnlessOracleFonts()
            let marker = Self.attributes("Apple SD Gothic Neo", 10)
            let objectOnly = Self.finish(
                [LineBoxFixtures.objectMarker(height: 30, attributes: marker)],
                endBox: Self.box("Menlo", 10)
            )
            let next = Self.finish([Self.text("다음", "Apple SD Gothic Neo", 10)])
            let alone = try Self.metrics(objectOnly)
            let combined = try XCTUnwrap(HwpCombinedBlockString.combine([objectOnly, next]))
            let first = try XCTUnwrap(Self.lines(combined).first)
            let joined = HwpDrawnTextLayout.lineMetrics(of: first.line, in: combined)
            expect(joined.boxHeight).to(beCloseTo(alone.boxHeight, within: 0.001))
            expect(joined.boxHeight).to(beCloseTo(30, within: 0.001))
            expect(combined.attribute(
                HwpAttributedStringKey.combinedParagraphSeparator, at: objectOnly.length,
                effectiveRange: nil
            )).toNot(beNil())
        }

        /// 장식선은 줄 상자의 **가장자리**와 **글자 상자의 cell**로 선다 — 10pt 밑줄 줄에 16pt 끝
        /// 글자가 쌓이면 밑줄은 상자 바닥에서 0.129 × 글자 cell 위(한글 PDF: 함초롬돋움 베이스라인
        /// 아래 9.36pt = 상자 바닥에서 1.71 위, 산식 1.68; 두께는 0.12pt 격자의 0.72, 산식 0.65 —
        /// 끝 상자의 cell이면 1.04), 글자 상자보다 낮은 개체가 베이스라인을
        /// 상자 바닥 가까이 내리면 밑줄이 **베이스라인 위로** 올라간다(Apple SD 20pt + 30pt 표: 한글
        /// PDF 1.80pt 위, 산식 1.90).
        func testDecorationBoxUsesTheLineEdgesAndTheTextCell() throws {
            try skipUnlessOracleFonts()
            let appleSD10 = Self.box("Apple SD Gothic Neo", 10)
            let menlo16 = Self.box("Menlo", 16)
            let stacked = Self.finish(
                [Self.text("가나다", "Apple SD Gothic Neo", 10)], endBox: menlo16
            )
            let line = try XCTUnwrap(Self.lines(stacked).first)
            let box = try XCTUnwrap(HwpDrawnTextLayout.msWordLineBox(of: line.line, endsParagraph: true))
            expect(box.cellHeight) == appleSD10.cellHeight
            expect(box.lineHeight).to(beCloseTo(
                menlo16.lineHeight + appleSD10.lineHeight - appleSD10.baseline, within: 0.001
            ))
            let underline = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box)
            expect(-underline.center).to(beCloseTo(
                box.lineHeight - box.baseline - 0.129 * appleSD10.cellHeight, within: 0.001
            ))
            expect(underline.thickness).to(beCloseTo(0.05 * appleSD10.cellHeight, within: 0.0001))
            let appleSD20 = Self.box("Apple SD Gothic Neo", 20)
            let band = Self.finish([
                Self.text("가나", "Apple SD Gothic Neo", 20),
                LineBoxFixtures.objectMarker(
                    height: 30, attributes: Self.attributes("Apple SD Gothic Neo", 20)
                ),
            ], endBox: Self.box("Menlo", 20))
            let bandLine = try XCTUnwrap(Self.lines(band).first)
            let bandBox = try XCTUnwrap(
                HwpDrawnTextLayout.msWordLineBox(of: bandLine.line, endsParagraph: true)
            )
            expect(bandBox.lineHeight).to(beCloseTo(appleSD20.lineHeight, within: 0.001))
            expect(bandBox.baseline).to(beCloseTo(30, within: 0.001))
            let bandUnderline = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: bandBox)
            expect(bandUnderline.center).to(beGreaterThan(0))
            expect(bandUnderline.center).to(beCloseTo(1.90, within: 0.12))
            // 위 밑줄은 줄 상자 윗변(개체 윗변)에서 0.129 cell 아래다 (한글 PDF: 30pt 표 줄의
            // 10pt 위 밑줄이 베이스라인 위 28.32pt = 30 − 1.68).
            let above = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: bandBox)
            expect(above.center).to(beCloseTo(30 - 0.129 * appleSD20.cellHeight, within: 0.001))
        }

        /// 조판 없이 잰 잉크 상한은 개체를 예약한 문자열에서 descent 전체를 아래 여유로 둔다 —
        /// 글자 상자 안쪽 개체가 베이스라인을 상자 바닥까지 내리면 줄 상자의 베이스라인 아래 몫이
        /// 어느 후보 상자보다도 작아진다.
        func testInkReachCoversObjectLinesWhoseBaselineSitsNearTheBoxBottom() throws {
            try skipUnlessOracleFonts()
            let font = Self.font("Apple SD Gothic Neo", 20)
            let marker = NSMutableAttributedString(
                attributedString: LineBoxFixtures.objectMarker(
                    height: 31, attributes: Self.attributes("Apple SD Gothic Neo", 20)
                )
            )
            marker.addAttribute(
                HwpAttributedStringKey.inlineObjectHeight, value: NSNumber(value: 31),
                range: NSRange(location: 0, length: marker.length)
            )
            let string = Self.finish([Self.text("가나", "Apple SD Gothic Neo", 20), marker])
            let reach = try XCTUnwrap(HwpHitTester.msWordVerticalInkReach(of: string))
            expect(reach.below).to(beGreaterThanOrEqualTo(CTFontGetDescent(font) - 0.001))
            let metrics = try Self.metrics(string)
            // 이 줄의 상자 아래 몫(0.20)은 글리프 descent보다 작아 잉크가 상자 밖으로 샌다.
            expect(metrics.boxHeight - metrics.baselineAnchor).to(beLessThan(CTFontGetDescent(font)))
        }
    }
#endif
