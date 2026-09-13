import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import XCTest

#if canImport(CoreText)
    /// 가드들이 공유하는 조판 입력 빌더와 **임계 오라클** — 프레임 높이를 줄여 줄이 떨어지는
    /// 임계를 이분 탐색하면 CT가 그 줄에 쓴 슬롯 높이가 나온다 (구현과 독립된 오라클).
    enum LineBoxFixtures {
        /// 10pt 한 줄 + 40pt 두 줄 — 줄마다 상자 높이가 다른 문단. 실물의 혼합 크기
        /// 문단과 같은 꼴이고, 공개 `HwpPaintCommand.drawText` 호출자가 문자열을 그대로
        /// 넘기는 경로이기도 하다.
        static func mixedSizeParagraph(
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

        // 스펙 목록을 그대로 싣는 문단 스타일 (비면 스타일 없음)

        /// 스펙 목록을 그대로 싣는 문단 스타일 (비면 스타일 없음)
        static func paragraphStyle(
            specs values: [(CTParagraphStyleSpecifier, CGFloat)],
            justified: Bool = false
        ) -> CTParagraphStyle? {
            guard !values.isEmpty || justified else { return nil }
            var alignment = justified ? CTTextAlignment.justified : .natural
            var numbers = values.map(\.1)
            return numbers.withUnsafeMutableBufferPointer { buffer in
                withUnsafeMutablePointer(to: &alignment) { alignmentPointer in
                    var settings = values.indices.map { index in
                        CTParagraphStyleSetting(
                            spec: values[index].0,
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

        static func baselines(
            _ string: NSAttributedString, lineWidth: CGFloat = 400
        ) -> [CGFloat] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100), lineWidth: lineWidth
            ).map(\.baselineOrigin.y)
        }

        // **상한만 지정된 문단은 못박힌 문단이 아니다** (#178 리뷰). 상한은 그 아래 높이를
        // 전혀 건드리지 않으므로 CT 조판이 그대로인데, 상한만을 못박힌 쪽으로 보면 청크 첫
        // 줄의 배치 ascent가 모든 줄에 적용돼 상자가 어긋난다 — 이 문단에서 무해한 상한
        // 1000을 얹으면 baseline이 `[108.5, 151.9, 199.9]` → `[108.5, 175.0, 223.0]`으로
        // 바뀌었다.

        /// 이 기기에서 leading이 0이 아닌 글꼴 이름 (없으면 nil). `CTFontCreateWithName`은
        /// 모르는 이름에 Helvetica(leading 0)를 주므로 leading 검사로 걸러진다.
        static func nameOfFontWithLeading() -> String? {
            for name in ["Hiragino Sans", "Times New Roman", "Arial", "Thonburi", "GeezaPro"] {
                let font = CTFontCreateWithName(name as CFString, 10, nil)
                if CTFontGetLeading(font) > 0.05 {
                    return name
                }
            }
            return nil
        }

        // CT가 첫 줄에 쓴 **슬롯 높이** — 첫 줄이 들어가는 최소 프레임 높이를 이분 탐색해
        // 잰다 (구현과 독립된 오라클).

        /// CT가 첫 줄에 쓴 **슬롯 높이** — 첫 줄이 들어가는 최소 프레임 높이를 이분 탐색해
        /// 잰다 (구현과 독립된 오라클).
        static func measuredFirstSlot(
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

        // CT 줄 origin의 baseline 간격 — 두 입력의 조판이 같은지 보는 전제 확인용.

        /// CT 줄 origin의 baseline 간격 — 두 입력의 조판이 같은지 보는 전제 확인용.
        static func coreTextDeltas(_ string: NSAttributedString) -> [Double] {
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

        static let paragraphWidth: CGFloat = 70

        // 한 종류 글자로만 된 여러 줄 문단 — 줄마다 상자가 같아 간격 규칙만 드러난다.

        /// 한 종류 글자로만 된 여러 줄 문단 — 줄마다 상자가 같아 간격 규칙만 드러난다.
        static func uniformParagraph(
            specs: [(CTParagraphStyleSpecifier, CGFloat)],
            fontName: String = "Helvetica",
            justified: Bool = false,
            repeats: Int = 3
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
                string: String(repeating: "Lorem ipsum dolor ", count: repeats),
                attributes: attributes
            )
        }

        // **양쪽 정렬 문단에서도 줄 전진량이 균일해야 한다.** CT는 양쪽 정렬 줄의
        // typographic bounds에 강제 줄 높이를 **적용하기 전** 값을 담는다 (하한 15pt·
        // Helvetica 10pt: 보고 descent 2.2998, 실제 배치 4.0). 보고값으로 복원하면 줄마다
        // 1.7pt 어긋나므로, 슬롯이 균일한 것이 관찰되면 첫 줄의 정확값을 그대로 쓴다.

        /// 문단 아래·위 간격을 실은 10pt 두 문단
        static func twoParagraphs(spacing: CGFloat, before: CGFloat) -> NSAttributedString {
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

        /// 지정 위치의 글자만 **기본 크기**가 다른 문단 (실제 조판 크기는 같다) — 상대크기
        /// 글자가 그렇게 조판된다. 슬롯은 같으므로 이월 ascent가 유효해야 한다.
        static func paragraphWithAnchorOnlySizeChange(
            at position: Int, fontName: String
        ) -> NSAttributedString {
            let style = paragraphStyle(specs: [(.minimumLineHeight, 10)])
            let body = String(repeating: "Lorem ipsum ", count: 8)
            let out = NSMutableAttributedString(
                string: String(body.prefix(position)),
                attributes: attributes(size: 10, style: style, fontName: fontName)
            )
            out.append(NSAttributedString(
                string: "X",
                attributes: attributes(size: 10, baseSize: 20, style: style, fontName: fontName)
            ))
            out.append(NSAttributedString(
                string: String(body.dropFirst(position + 1)),
                attributes: attributes(size: 10, style: style, fontName: fontName)
            ))
            return out
        }

        /// 지정 위치에 60pt 글자처럼 취급 개체가 든 하한 20pt 문단 — 청크가 그 줄을 미완으로
        /// 버리면 다음 청크에서 개체가 그 줄에 들어온다.
        static func paragraphWithObject(at position: Int) -> NSAttributedString {
            let style = paragraphStyle(specs: [(.minimumLineHeight, 20)])
            let body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi"
            let head = String(body.prefix(position))
            let tail = String(body.dropFirst(position))
            let out = NSMutableAttributedString(
                string: head, attributes: attributes(size: 10, style: style)
            )
            if let delegate = HwpInlineObjectReservation.runDelegate(width: 20, height: 60) {
                var marker = attributes(size: 10, style: style)
                marker[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
                marker[HwpAttributedStringKey.controlIndex] = NSNumber(value: 0)
                out.append(NSAttributedString(string: "\u{FFFC}", attributes: marker))
            }
            out.append(NSAttributedString(
                string: tail, attributes: attributes(size: 10, style: style)
            ))
            return out
        }

        /// 하한 20pt·양쪽 정렬 문단 — 마지막 글자만 40pt라 줄 상자가 갈린다.
        static func justifiedTailParagraph() -> NSAttributedString {
            let style = paragraphStyle(specs: [(.minimumLineHeight, 20)], justified: true)
            let body = NSMutableAttributedString(
                string: "abcd efgh ijkl mnop qrst uvwx yzab",
                attributes: attributes(size: 10, style: style)
            )
            body.append(NSAttributedString(
                string: "W", attributes: attributes(size: 40, style: style)
            ))
            return body
        }

        /// 20pt로 못박은 한 줄 문단 + 60pt로 못박은 문단 (한 줄 또는 두 줄)
        static func twoPinnedParagraphs(extraLine: Bool) -> NSAttributedString {
            let first = paragraphStyle(specs: [(.minimumLineHeight, 20), (.maximumLineHeight, 20)])
            let second = paragraphStyle(
                specs: [(.minimumLineHeight, 60), (.maximumLineHeight, 60)]
            )
            let body = NSMutableAttributedString(
                string: "alpha\n", attributes: attributes(size: 10, style: first)
            )
            body.append(NSAttributedString(
                string: extraLine ? "beta\ngamma" : "beta",
                attributes: attributes(size: 10, style: second)
            ))
            return body
        }

        static func attributes(
            size: CGFloat,
            baseSize: CGFloat? = nil,
            style: CTParagraphStyle?,
            fontName: String = "Helvetica"
        ) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName(fontName as CFString, size, nil),
                HwpAttributedStringKey.baseFontSize: NSNumber(
                    value: Double(baseSize ?? size)
                ),
            ]
            if let style {
                attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key] = style
            }
            return attributes
        }
    }
#endif
