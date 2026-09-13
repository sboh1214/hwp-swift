import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 줄마다 상자 높이가 다른 문단의 **상자 상단** 계약 (#178 리뷰).
    ///
    /// 앵커 자체는 `HwpBaselineAnchorTests`가 잠근다. 여기서 잠그는 것은 그 앵커를 걸 자리,
    /// 즉 CT 슬롯에서 복원한 **배치 ascent**다 — 줄 높이를 못박지 않은 문단 (`.atLeast`·
    /// 개체 문단·공개 `HwpPaintCommand.drawText` 호출자) 은 줄마다 슬롯이 달라 여기가
    /// 어긋나면 글자가 상자를 벗어난다.
    ///
    /// 오라클은 CT 자신이다 — 프레임 높이를 줄여 줄이 떨어지는 임계를 이분 탐색하면 CT의
    /// 실제 슬롯 경계가 나온다 (2026-09-13 실측). 그 경계가 말해 주는 것이 이 스위트가 지키는
    /// 규칙이다: 슬롯의 baseline 아래 몫은 보고 **descent**이고 (`leading`은 위쪽 몫이며 보고
    /// **ascent**는 배치값이 아니다), 문단 간격·줄 뒤 간격은 다음 슬롯의 ascent 안에 들어
    /// 있어 걷어내야 하며, 그 간격은 줄 간격 하한·상한에 갇힌 **유효** 값이다.
    ///
    /// 균일한 문단은 이 복원식을 타지 않으므로 (`hasUniformSlots`) 여기 가드들은 **줄마다
    /// 상자가 다른** 문단을 쓴다 — 균일한 입력으로 잠그면 판별력이 없다.
    final class HwpLineBoxAdvanceTests: XCTestCase {
        /// 10pt 한 줄 + 40pt 두 줄 — 줄마다 상자 높이가 다른 문단. 실물의 혼합 크기
        /// 문단과 같은 꼴이고, 공개 `HwpPaintCommand.drawText` 호출자가 문자열을 그대로
        /// 넘기는 경로이기도 하다.
        private static func mixedSizeParagraph(
            minimumLineHeight: CGFloat? = nil,
            maximumLineHeight: CGFloat? = nil,
            spacing: [(CTParagraphStyleSpecifier, CGFloat)] = [],
            fontName: String = "Helvetica"
        ) -> NSAttributedString {
            func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
                var attributes: [NSAttributedString.Key: Any] = [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName(fontName as CFString, size, nil),
                    HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(size)),
                ]
                var specs = spacing
                if let minimumLineHeight {
                    specs.append((.minimumLineHeight, minimumLineHeight))
                }
                if let maximumLineHeight {
                    specs.append((.maximumLineHeight, maximumLineHeight))
                }
                if let style = paragraphStyle(specs: specs) {
                    attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] = style
                }
                return attributes
            }
            let string = NSMutableAttributedString(string: "ab\n", attributes: attributes(10))
            string.append(NSAttributedString(string: "cd\n", attributes: attributes(40)))
            string.append(NSAttributedString(string: "ef", attributes: attributes(40)))
            return string
        }

        /// 스펙 목록을 그대로 싣는 문단 스타일 (비면 스타일 없음)
        private static func paragraphStyle(
            specs values: [(CTParagraphStyleSpecifier, CGFloat)]
        ) -> CTParagraphStyle? {
            guard !values.isEmpty else { return nil }
            var numbers = values.map(\.1)
            return numbers.withUnsafeMutableBufferPointer { buffer in
                let settings = values.indices.map { index in
                    CTParagraphStyleSetting(
                        spec: values[index].0,
                        valueSize: MemoryLayout<CGFloat>.size,
                        // swiftlint:disable:next force_unwrapping
                        value: buffer.baseAddress! + index
                    )
                }
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }

        private func baselines(
            _ string: NSAttributedString, lineWidth: CGFloat = 400
        ) -> [CGFloat] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: lineWidth
            ).map(\.baselineOrigin.y)
        }

        /// **상한만 지정된 문단은 못박힌 문단이 아니다** (#178 리뷰). 상한은 그 아래 높이를
        /// 전혀 건드리지 않으므로 CT 조판이 그대로인데, 상한만을 못박힌 쪽으로 보면 청크 첫
        /// 줄의 배치 ascent가 모든 줄에 적용돼 상자가 어긋난다 — 이 문단에서 무해한 상한
        /// 1000을 얹으면 baseline이 `[108.5, 151.9, 199.9]` → `[108.5, 175.0, 223.0]`으로
        /// 바뀌었다.
        func testNoOpMaximumLineHeightMovesNoLine() {
            let plain = baselines(Self.mixedSizeParagraph())
            let capped = baselines(Self.mixedSizeParagraph(maximumLineHeight: 1000))
            expect(plain.count).to(equal(3))
            expect(capped.map(Double.init))
                .to(beCloseTo(plain.map(Double.init), within: 0.001))
        }

        /// **하한이 걸린 줄과 자연 높이가 더 큰 줄은 슬롯이 다르다** (#178 리뷰).
        /// 10pt 상자에 하한 20을 걸면 한글의 전진량은 `max(상자, 하한)` = 20pt이고, 뒤따르는
        /// 40pt 줄은 하한보다 크므로 자기 자연 슬롯을 쓴다. 줄별 **보고** ascent로 상자를
        /// 찾던 종전 구현은 CT가 늘린 슬롯의 여분을 보고에서 빼먹어 둘째 줄 상자를 8.2pt
        /// 아래에 뒀다.
        func testMinimumOnlyLineHeightAdvancesShortLinesByTheMinimum() {
            let baselines = baselines(Self.mixedSizeParagraph(minimumLineHeight: 20))
            expect(baselines.count).to(equal(3))
            guard baselines.count == 3 else { return }
            // 첫 줄 상자(10pt)는 블록 상단에 핀한다.
            expect(Double(baselines[0])).to(beCloseTo(100 + 8.5, within: 0.001))
            // 둘째 줄 상자 상단 = 100 + max(10, 20) → baseline은 그 아래 0.85 × 40.
            expect(Double(baselines[1])).to(beCloseTo(100 + 20 + 34, within: 0.01))
        }

        /// **줄 간격 하한·상한을 적용한 유효 간격을 써야 한다** (#178 리뷰). CT는
        /// `lineSpacingAdjustment`를 `minimumLineSpacing`·`maximumLineSpacing`으로 가두므로,
        /// 상한 4에 간격 4와 10을 준 두 문단은 CT에서 **같은 자리**에 조판된다 — 원시 간격을
        /// 그대로 빼던 동안에는 우리가 그 둘을 6pt 다르게 그렸다. 하한도 같다(간격 0과 2가
        /// 하한 8 아래에서 같다).
        func testLineSpacingBoundsMakeEqualCoreTextLayoutsEqual() {
            for pair in [
                (a: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(4)),
                     (.maximumLineSpacing, 4)],
                 b: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(10)),
                     (.maximumLineSpacing, 4)]),
                (a: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(0)),
                     (.minimumLineSpacing, 8)],
                 b: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(2)),
                     (.minimumLineSpacing, 8)]),
            ] {
                // 줄마다 상자가 다른 문단이어야 복원식을 타 간격 계산이 드러난다 —
                // 균일한 문단은 슬롯이 균일해 첫 줄의 정확값만으로 배치된다.
                let first = Self.mixedSizeParagraph(spacing: pair.a)
                let second = Self.mixedSizeParagraph(spacing: pair.b)
                // 전제: CT가 둘을 같은 자리에 조판한다 (줄 origin 델타가 같다).
                expect(Self.coreTextDeltas(first)).to(
                    beCloseTo(Self.coreTextDeltas(second), within: 0.001),
                    description: "CT 조판이 같아야 이 가드가 뜻이 있다"
                )
                let firstBaselines = baselines(first, lineWidth: Self.paragraphWidth)
                let secondBaselines = baselines(second, lineWidth: Self.paragraphWidth)
                expect(firstBaselines.map(Double.init))
                    .to(beCloseTo(secondBaselines.map(Double.init), within: 0.001))
            }
        }

        /// **글꼴 leading은 baseline 아래 몫이 아니다** (#178 리뷰). CT는 leading을 슬롯의
        /// baseline **위**에 넣으므로 `descent + leading`을 아래 몫으로 쓰면 leading이 있는
        /// 글꼴에서 상자가 그만큼 어긋난다 (Hiragino Sans 5.0pt·Times New Roman 0.42pt·
        /// Arial 0.33pt). 오라클은 CT 자신이다 — 프레임 높이를 줄여 첫 줄이 떨어지는 임계가
        /// 곧 첫 슬롯 높이이고, 그것이 첫 줄에서 둘째 줄 상자까지의 전진량이다.
        func testFontLeadingIsNotCountedBelowTheBaseline() throws {
            let name = try XCTUnwrap(
                Self.nameOfFontWithLeading(), "leading이 있는 글꼴이 없는 기기"
            )
            // 줄마다 상자가 다른 문단이어야 복원식을 타 아래쪽 몫이 드러난다.
            let string = Self.mixedSizeParagraph(fontName: name)
            let lines = baselines(string, lineWidth: 400)
            expect(lines.count).to(equal(3))
            guard lines.count == 3 else { return }
            // 첫 줄 상자 전진량 = CT가 첫 줄에 쓴 슬롯 (임계 오라클).
            let slot = try XCTUnwrap(Self.measuredFirstSlot(string, width: 400))
            let secondBoxTop = lines[1] - 40 * HwpRenderTuning.Text.baselineAnchorRatio
            expect(Double(secondBoxTop - 100)).to(beCloseTo(Double(slot), within: 0.01))
        }

        /// 이 기기에서 leading이 0이 아닌 글꼴 이름 (없으면 nil). `CTFontCreateWithName`은
        /// 모르는 이름에 Helvetica(leading 0)를 주므로 leading 검사로 걸러진다.
        private static func nameOfFontWithLeading() -> String? {
            for name in ["Hiragino Sans", "Times New Roman", "Arial", "Thonburi", "GeezaPro"] {
                let font = CTFontCreateWithName(name as CFString, 10, nil)
                if CTFontGetLeading(font) > 0.05 {
                    return name
                }
            }
            return nil
        }

        /// CT가 첫 줄에 쓴 **슬롯 높이** — 첫 줄이 들어가는 최소 프레임 높이를 이분 탐색해
        /// 잰다 (구현과 독립된 오라클).
        private static func measuredFirstSlot(
            _ string: NSAttributedString, width: CGFloat = paragraphWidth
        ) -> CGFloat? {
            func fits(_ height: CGFloat) -> Bool {
                let framesetter = CTFramesetterCreateWithAttributedString(string)
                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRange(location: 0, length: string.length),
                    CGPath(
                        rect: CGRect(x: 0, y: 0, width: width, height: height),
                        transform: nil
                    ), nil
                )
                return ((CTFrameGetLines(frame) as? [CTLine]) ?? []).count >= 1
            }
            var low: CGFloat = 0
            var high: CGFloat = 200
            guard fits(high) else { return nil }
            while high - low > 0.001 {
                let middle = (low + high) / 2
                if fits(middle) {
                    high = middle
                } else {
                    low = middle
                }
            }
            return high
        }

        /// CT 줄 origin의 baseline 간격 — 두 입력의 조판이 같은지 보는 전제 확인용.
        private static func coreTextDeltas(_ string: NSAttributedString) -> [Double] {
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: string.length), nil,
                CGSize(width: paragraphWidth, height: .greatestFiniteMagnitude), nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: string.length),
                CGPath(
                    rect: CGRect(
                        x: 0, y: 0, width: paragraphWidth, height: max(ceil(suggested.height), 1)
                    ), transform: nil
                ), nil
            )
            guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            return zip(origins.dropFirst(), origins).map { Double($1.y - $0.y) }
        }

        private static let paragraphWidth: CGFloat = 70

        /// 한 종류 글자로만 된 여러 줄 문단 — 줄마다 상자가 같아 간격 규칙만 드러난다.
        private static func uniformParagraph(
            specs: [(CTParagraphStyleSpecifier, CGFloat)],
            fontName: String = "Helvetica",
            justified: Bool = false
        ) -> NSAttributedString {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName(fontName as CFString, 10, nil),
                HwpAttributedStringKey.baseFontSize: NSNumber(value: 10.0),
            ]
            if !specs.isEmpty || justified {
                var values = specs.map(\.1)
                var alignment = justified ? CTTextAlignment.justified : .natural
                attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] =
                    values.withUnsafeMutableBufferPointer { buffer in
                        withUnsafeMutablePointer(to: &alignment) { alignmentPointer in
                            var settings = specs.indices.map { index in
                                CTParagraphStyleSetting(
                                    spec: specs[index].0,
                                    valueSize: MemoryLayout<CGFloat>.size,
                                    // swiftlint:disable:next force_unwrapping
                                    value: buffer.baseAddress! + index
                                )
                            }
                            settings.append(CTParagraphStyleSetting(
                                spec: .alignment,
                                valueSize: MemoryLayout<CTTextAlignment>.size,
                                value: alignmentPointer
                            ))
                            return CTParagraphStyleCreate(settings, settings.count)
                        }
                    }
            }
            return NSAttributedString(
                string: String(repeating: "Lorem ipsum dolor ", count: 3), attributes: attributes
            )
        }

        /// **양쪽 정렬 문단에서도 줄 전진량이 균일해야 한다.** CT는 양쪽 정렬 줄의
        /// typographic bounds에 강제 줄 높이를 **적용하기 전** 값을 담는다 (하한 15pt·
        /// Helvetica 10pt: 보고 descent 2.2998, 실제 배치 4.0). 보고값으로 복원하면 줄마다
        /// 1.7pt 어긋나므로, 슬롯이 균일한 것이 관찰되면 첫 줄의 정확값을 그대로 쓴다.
        func testJustifiedClampedParagraphKeepsAUniformAdvance() {
            let string = Self.uniformParagraph(
                specs: [(.minimumLineHeight, 15)], justified: true
            )
            let lines = baselines(string, lineWidth: Self.paragraphWidth)
            expect(lines.count).to(beGreaterThan(2))
            guard lines.count > 2 else { return }
            let gaps = zip(lines.dropFirst(), lines).map { Double($0 - $1) }
            expect(gaps).to(beCloseTo(Array(repeating: 15.0, count: gaps.count), within: 0.01))
        }

        /// 같은 문단은 **청크를 어떻게 나눠도** 같은 자리에 그려져야 한다 — `maxLineFrames`는
        /// 문자 예산이라 작은 값이 청크를 쪼갠다. 균일한 문단은 청크마다 CT 첫 줄 슬롯 특례를
        /// 새로 타므로, 그 특례가 전진량에 새면 경계마다 자리가 밀린다.
        func testChunkBudgetDoesNotMoveAUniformParagraph() {
            let string = Self.uniformParagraph(specs: [(.minimumLineHeight, 15)])
            let whole = HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100),
                lineWidth: Self.paragraphWidth
            ).map(\.baselineOrigin.y)
            for budget in [20, 40, 80] {
                let chunked = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: CGPoint(x: 0, y: 100),
                    lineWidth: Self.paragraphWidth, maxLineFrames: budget
                ).map(\.baselineOrigin.y)
                expect(chunked.count).to(equal(whole.count), description: "예산 \(budget)")
                guard chunked.count == whole.count else { continue }
                expect(chunked.map(Double.init)).to(
                    beCloseTo(whole.map(Double.init), within: 0.01), description: "예산 \(budget)"
                )
            }
        }

        /// **문단 간격은 상자 사이에 남는다.** CT는 문단 아래·위 간격을 다음 줄 슬롯의
        /// ascent 안에 넣으므로 (실측: 간격 6+4를 준 둘째 문단 첫 줄의 배치 ascent가
        /// 9.70 → 19.70) 배치 ascent 복원에서 걷어내야 한다. 걷어내지 않으면 간격이 사라져
        /// 둘째 문단이 그만큼 올라간다 — 한글은 줄 간격 여분을 상자 아래 `lineSpacing`으로
        /// 적고 다음 상자를 그 아래에 둔다.
        func testParagraphSpacingStaysBetweenLineBoxes() {
            let plain = baselines(Self.twoParagraphs(spacing: 0, before: 0))
            let spaced = baselines(Self.twoParagraphs(spacing: 6, before: 4))
            expect(plain.count).to(equal(2))
            expect(spaced.count).to(equal(2))
            guard plain.count == 2, spaced.count == 2 else { return }
            expect(Double(spaced[0])).to(beCloseTo(Double(plain[0]), within: 0.001))
            expect(Double(spaced[1] - plain[1])).to(beCloseTo(10, within: 0.001))
        }

        /// 문단 아래·위 간격을 실은 10pt 두 문단
        private static func twoParagraphs(spacing: CGFloat, before: CGFloat) -> NSAttributedString {
            var values: [(CTParagraphStyleSpecifier, CGFloat)] = [
                (.paragraphSpacing, spacing), (.paragraphSpacingBefore, before),
            ]
            var numbers = values.map(\.1)
            let style = numbers.withUnsafeMutableBufferPointer { buffer in
                let settings = values.indices.map { index in
                    CTParagraphStyleSetting(
                        spec: values[index].0,
                        valueSize: MemoryLayout<CGFloat>.size,
                        // swiftlint:disable:next force_unwrapping
                        value: buffer.baseAddress! + index
                    )
                }
                return CTParagraphStyleCreate(settings, settings.count)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, 10, nil),
                HwpAttributedStringKey.baseFontSize: NSNumber(value: 10.0),
                kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ]
            return NSAttributedString(string: "ab\ncd", attributes: attributes)
        }
    }
#endif
