import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 가용 폭보다 넓은 줄의 시작 자리 (#254) — 한글은 줄보다 넓은 줄(개체 줄이든 글자 하나가 넓은
    /// 글줄이든)을 문단 정렬과 무관하게 **줄 시작**(문단 왼쪽 여백 + 첫 줄이면 들여쓰기)에 둔다. CT는
    /// 가운데·오른쪽 정렬 줄을 남는 폭(음수)만큼 왼쪽으로 민다. 공유 줄바꿈 코어가 고치므로
    /// 측정·렌더가 함께 따른다.
    final class HwpOverflowLineStartTests: XCTestCase {
        /// 폭 `width`인 개체 마커(run delegate) 하나 + `tail` 문자열 — 정렬·들여쓰기를 준 문단 스타일
        static func string(
            objectWidth width: CGFloat,
            prefix: String = "",
            tail: String = "",
            alignment: CTTextAlignment,
            firstLineHeadIndent: CGFloat = 0,
            headIndent: CGFloat = 0
        ) -> NSAttributedString {
            let style = paragraphStyle(
                alignment: alignment,
                firstLineHeadIndent: firstLineHeadIndent,
                headIndent: headIndent
            )
            let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)
            let base: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ]
            let result = NSMutableAttributedString(string: prefix, attributes: base)
            var marker = base
            marker[kCTRunDelegateAttributeName as NSAttributedString.Key] =
                HwpInlineObjectReservation.runDelegate(width: width, height: 15)
            result.append(NSAttributedString(string: "\u{FFFC}", attributes: marker))
            result.append(NSAttributedString(string: tail, attributes: base))
            return result
        }

        /// 정렬·첫 줄 들여쓰기·들여쓰기만 준 CT 문단 스타일
        static func paragraphStyle(
            alignment: CTTextAlignment,
            firstLineHeadIndent: CGFloat,
            headIndent: CGFloat
        ) -> CTParagraphStyle {
            var alignmentValue = alignment
            var first = firstLineHeadIndent
            var head = headIndent
            return withUnsafeBytes(of: &alignmentValue) { alignmentBytes in
                withUnsafeBytes(of: &first) { firstBytes in
                    withUnsafeBytes(of: &head) { headBytes in
                        let settings = [
                            CTParagraphStyleSetting(
                                spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                value: alignmentBytes.baseAddress!
                            ),
                            CTParagraphStyleSetting(
                                spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size,
                                value: firstBytes.baseAddress!
                            ),
                            CTParagraphStyleSetting(
                                spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size,
                                value: headBytes.baseAddress!
                            ),
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }

        /// 공유 코어의 줄 origin x와 각 줄의 문자 범위
        static func lines(
            _ string: NSAttributedString, lineWidth: CGFloat
        ) -> [(x: CGFloat, range: CFRange)] {
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            guard let chunk = HwpLineBreaker.nextFrameChunk(
                framesetter: framesetter, typesetter: typesetter, attributedString: string,
                startLocation: 0, fullLength: string.length, remainingLineBudget: 100,
                lineWidth: lineWidth
            ) else { return [] }
            return (0 ..< chunk.keepCount).map {
                (chunk.origins[$0].x, CTLineGetStringRange(chunk.lines[$0]))
            }
        }

        /// 한글: 본문 425.2pt의 가운데·오른쪽 정렬 줄에 450pt 표가 혼자 놓이면 줄 시작(0)에서 시작한다
        /// (CT: −12.4·−24.8). 뒤 글자는 다음 줄로 가서 그 줄의 정렬을 따른다.
        func testOverflowingCenteredAndRightAlignedLinesStartAtTheLineStart() {
            for alignment in [CTTextAlignment.center, .right] {
                let lines = Self.lines(
                    Self.string(objectWidth: 450, tail: "뒤", alignment: alignment), lineWidth: 425.2
                )
                expect(lines.count).to(equal(2), description: "\(alignment)")
                guard lines.count == 2 else { continue }
                expect(lines[0].x).to(equal(0), description: "\(alignment)")
                expect(lines[1].x).to(beGreaterThan(200), description: "\(alignment) 뒤 글자 줄")
            }
        }

        /// 줄 시작은 문단 왼쪽 여백(`headIndent`)이고, 문단 첫 줄이면 들여쓰기를 더한
        /// `firstLineHeadIndent`다 — 한글: 왼쪽 여백 20pt면 105.12, 들여쓰기 20pt면 105.12 (본문 85.08).
        func testOverflowingLineStartsAtTheParagraphIndent() {
            let first = Self.lines(
                Self.string(
                    objectWidth: 450, alignment: .center, firstLineHeadIndent: 30, headIndent: 20
                ),
                lineWidth: 425.2
            )
            expect(first.first?.x) == 30
            // 둘째 줄이면 headIndent — 앞 글자가 첫 줄을 차지하고 개체가 둘째 줄로 넘어간다
            let second = Self.lines(
                Self.string(
                    objectWidth: 450, prefix: "가나다", alignment: .right,
                    firstLineHeadIndent: 30, headIndent: 20
                ),
                lineWidth: 425.2
            )
            expect(second.count).to(beGreaterThanOrEqualTo(2))
            guard second.count >= 2 else { return }
            expect(second[1].x) == 20
        }

        /// 한 줄 끝(U+000A) 뒤는 CT 문단이 새로 시작해 첫 줄 들여쓰기에 놓인다 — 측정·렌더가 그 줄을
        /// 같은 규약으로 다루므로 넘친 줄의 시작도 그 들여쓰기다.
        func testOverflowingLineAfterAHardLineBreakStartsAtTheFirstLineIndent() {
            let lines = Self.lines(
                Self.string(
                    objectWidth: 450, prefix: "가\n", alignment: .center,
                    firstLineHeadIndent: 30, headIndent: 20
                ),
                lineWidth: 425.2
            )
            let marker = lines.first { $0.range.location == 2 }
            expect(marker?.x) == 30
        }

        /// 넘치지 않는 줄은 CT 정렬 그대로다 — 가운데 정렬 400pt 줄은 (425.2 − 400) / 2 = 12.6.
        func testFittingLinesKeepTheirAlignment() {
            let lines = Self.lines(
                Self.string(objectWidth: 400, alignment: .center), lineWidth: 425.2
            )
            expect(lines.first?.x).to(beCloseTo(12.6, within: 1e-6))
            let left = Self.lines(Self.string(objectWidth: 450, alignment: .left), lineWidth: 425.2)
            expect(left.first?.x) == 0
        }

        /// 개체가 없는 글줄도 같다 (#254 PR 리뷰 실측, `probes/254/review`) — 한글은 문단 폭 125.2pt의
        /// 150pt '가'와 칸 폭 40pt 셀의 60pt '다'를 왼쪽·가운데·오른쪽 정렬 모두 줄 시작에 둔다(CT 정렬
        /// 오프셋대로면 가운데 −10.2·−9.1pt, 오른쪽 −20.3·−18.2pt). 리뷰는 이 보정을 개체 줄로 좁히자고
        /// 했지만 실측이 반증했다. 나눌 수 없는 글자 하나(400pt `W`, 240.8pt)가 가용 폭 180pt(줄 200pt −
        /// 들여쓰기 20pt)를 넘는 줄은 정렬과 무관하게 20에서 시작하고, 넘치지 않는 100pt `W`는 정렬대로
        /// 놓인다.
        func testOverflowingGlyphLinesWithoutObjectsAlsoStartAtTheLineStart() {
            func line(_ size: CGFloat, _ alignment: CTTextAlignment) -> CGFloat? {
                let string = NSAttributedString(string: "W", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key:
                        CTFontCreateWithName("Menlo" as CFString, size, nil),
                    kCTParagraphStyleAttributeName as NSAttributedString.Key: Self.paragraphStyle(
                        alignment: alignment, firstLineHeadIndent: 20, headIndent: 20
                    ),
                ])
                let lines = Self.lines(string, lineWidth: 200)
                return lines.count == 1 ? lines[0].x : nil
            }
            for alignment in [CTTextAlignment.left, .center, .right] {
                expect(line(400, alignment)).to(equal(20), description: "\(alignment)")
            }
            expect(line(100, .center) ?? 0).to(beGreaterThan(60))
            expect(line(100, .right) ?? 0).to(beGreaterThan(line(100, .center) ?? 0))
        }

        /// 개체만으로 줄의 **가용 폭**(컨테이너 폭 − 첫 줄 들여쓰기)을 넘는 줄은 slight-overflow 한 줄
        /// 허용이 아니다 — 문단 폭 405.2pt(왼쪽 여백 20)의 415pt 표 + 뒤 글자는 컨테이너 425.2pt를 살짝
        /// 넘을 뿐이지만 개체가 줄에 안 들어가므로 공유 코어가 줄 시작(20)에 두고 뒤 글자를 다음 줄로
        /// 보낸다. 한 줄씩 들어가는 개체 둘(220 + 220pt)도 합이 가용 폭을 넘으면 마찬가지다. 개체가
        /// 줄에 들어가고 글자까지 더해 살짝 넘치는 줄(글꼴 차)은 종전대로 허용이다.
        func testObjectsOverflowingTheAvailableWidthAreNotSlightOverflow() {
            let indented = Self.string(
                objectWidth: 415, tail: "뒤뒤", alignment: .center,
                firstLineHeadIndent: 20, headIndent: 20
            )
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: indented, lineWidth: 425.2
            )).to(beNil())
            let lines = Self.lines(indented, lineWidth: 425.2)
            expect(lines.count) == 2
            expect(lines.first?.x) == 20

            let pair = NSMutableAttributedString(
                attributedString: Self.string(objectWidth: 220, alignment: .center)
            )
            pair.append(Self.string(objectWidth: 220, alignment: .center))
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: pair, lineWidth: 425.2
            )).to(beNil())

            let fitting = Self.string(objectWidth: 400, tail: "가나다", alignment: .center)
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: fitting, lineWidth: 425.2
            )).notTo(beNil())
        }

        /// 렌더(`HwpDrawnTextLayout.lines`)도 같은 코어의 origin을 쓴다 — 넘친 줄의 그려지는 x가 줄 시작이다.
        func testDrawnLinesFollowTheSharedOrigin() {
            let string = Self.string(objectWidth: 450, alignment: .right, firstLineHeadIndent: 20)
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 85.04, y: 0), lineWidth: 425.2
            )
            expect(drawn.first?.baselineOrigin.x).to(beCloseTo(105.04, within: 1e-6))
        }
    }
#endif
