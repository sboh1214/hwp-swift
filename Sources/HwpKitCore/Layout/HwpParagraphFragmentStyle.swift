import CoreGraphics
import CoreText
import Foundation

// 문단의 이어지는 조각(쪽·단 경계 뒤 부분 문자열)의 문단 스타일 (#154 리뷰)

public extension HwpParagraphLayout {
    /// 문단 조판 문자열의 `range` 조각 — 문단 첫머리가 아닌 **이어지는 조각**이면 첫 줄
    /// 들여쓰기를 둘째 줄 들여쓰기로 맞춘 문단 스타일 사본을 첫 CT 문단에 단다.
    ///
    /// 조각은 독립 CT 프레임으로 다시 조판되므로 문단 스타일의 `firstLineHeadIndent`
    /// 가 조각 첫 줄에 다시 걸린다. 한글은 이어지는 쪽·단의 첫 줄을 문단 첫 줄이
    /// 아니라 이어지는 줄로 두므로(들여쓰기 문단은 여백에서, 자동 내어쓰기 번호
    /// 문단은 본문 시작에서 이어진다) `firstLineHeadIndent`를 `headIndent`로 바꾼다 —
    /// 측정(`layout`)은 문단 전체를 한 프레임으로 재 그 줄을 이미 `headIndent`에
    /// 두었으므로 조각의 줄바꿈도 측정과 같아진다.
    ///
    /// 바꾸는 범위는 조각의 **첫 CT 문단**(첫 문단 구분자까지)뿐이다 — 한 줄 끝(코드
    /// 10, `\n`)이나 본문의 U+2029 뒤는 측정에서도 CT 문단이 새로 시작해
    /// `firstLineHeadIndent`에 놓이므로 원래 스타일을 유지해야 줄바꿈이 같다. 같은
    /// 이유로 조각이 문단 구분자 바로 뒤에서 시작하면 첫 줄도 원래대로 둔다. 경계의
    /// 문단 정의는 `NSString.getParagraphStart`·CoreText와 같은 LF·CR·CRLF·U+2029다 —
    /// `\n`만 보면 U+2029 뒤 줄까지 보정돼 줄 수가 갈린다. 문단 첫머리 조각, 두
    /// 들여쓰기가 같은 문단, 스타일 없는 문자열은 그대로 잘라 돌려준다.
    ///
    /// **비용은 조각 길이에 비례한다.** 직전 글자 하나로 문단 시작 여부를 판정하고
    /// 첫 구분자는 조각 안에서만 찾는다 — `getParagraphStart`처럼 원문에서 앞뒤
    /// 구분자를 찾으면 줄바꿈 없는 긴 문단에서 조각마다 원문 전체를 훑어 분할 비용이
    /// 이차로 는다(리뷰 실측: 3,000자 조각으로 500만 자를 나누면 20초). 들여쓰기가
    /// 같은 문단은 탐색 전에 돌아간다.
    static func continuationFragment(
        of attributedString: NSAttributedString, range: NSRange
    ) -> NSAttributedString {
        let fragment = attributedString.attributedSubstring(from: range)
        let string = attributedString.string as NSString
        guard range.location > 0, fragment.length > 0,
              !isParagraphSeparator(string.character(at: range.location - 1)),
              let value = fragment.attribute(
                  kCTParagraphStyleAttributeName as NSAttributedString.Key, at: 0,
                  effectiveRange: nil
              ), CFGetTypeID(value as CFTypeRef) == CTParagraphStyleGetTypeID()
        else { return fragment }
        let style = value as! CTParagraphStyle // swiftlint:disable:this force_cast
        let firstLine = floatValue(.firstLineHeadIndent, of: style)
        let head = floatValue(.headIndent, of: style)
        guard abs(firstLine - head) > 0.001 else { return fragment }

        // 첫 CT 문단 = 조각 시작부터 조각 안 첫 구분자(포함, CRLF는 둘 다)까지 —
        // 구분자가 없으면 조각 전체.
        let firstParagraphLength = firstParagraphEnd(in: fragment.string as NSString)
        let mutable = NSMutableAttributedString(attributedString: fragment)
        mutable.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: continuationStyle(of: style, headIndent: head),
            range: NSRange(location: 0, length: firstParagraphLength)
        )
        return mutable
    }

    /// `ctParagraphStyle(from:property:)`가 싣는 설정을 그대로 옮기되 첫 줄
    /// 들여쓰기만 `headIndent`로 바꾼 스타일.
    private static func continuationStyle(
        of style: CTParagraphStyle, headIndent: CGFloat
    ) -> CTParagraphStyle {
        var alignment = CTTextAlignment.natural
        CTParagraphStyleGetValueForSpecifier(
            style, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment
        )
        var floats: [(CTParagraphStyleSpecifier, CGFloat)] = [
            (.firstLineHeadIndent, headIndent),
            (.headIndent, headIndent),
        ]
        for specifier in [
            CTParagraphStyleSpecifier.tailIndent, .paragraphSpacingBefore, .paragraphSpacing,
            .lineSpacingAdjustment, .maximumLineSpacing, .minimumLineHeight, .maximumLineHeight,
        ] {
            floats.append((specifier, floatValue(specifier, of: style)))
        }
        // Get 규칙(미보유 참조)이라 `CFArray?`로 바로 받으면 ARC가 한 번 더 놓아
        // 크래시한다 — Unmanaged로 받아 보유하지 않은 채 읽는다.
        var unretainedTabStops: Unmanaged<CFArray>?
        CTParagraphStyleGetValueForSpecifier(
            style, .tabStops, MemoryLayout<Unmanaged<CFArray>?>.size, &unretainedTabStops
        )
        let tabStops = unretainedTabStops?.takeUnretainedValue()

        let alignmentPointer = allocated(alignment)
        let floatPointers = floats.map { allocated($0.1) }
        let tabPointer = tabStops.map { allocated($0) }
        defer {
            alignmentPointer.deinitialize(count: 1)
            alignmentPointer.deallocate()
            for pointer in floatPointers {
                pointer.deinitialize(count: 1)
                pointer.deallocate()
            }
            tabPointer?.deinitialize(count: 1)
            tabPointer?.deallocate()
        }
        var settings = [CTParagraphStyleSetting(
            spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer
        )]
        for (index, entry) in floats.enumerated() {
            settings.append(CTParagraphStyleSetting(
                spec: entry.0, valueSize: MemoryLayout<CGFloat>.size, value: floatPointers[index]
            ))
        }
        if let tabPointer {
            settings.append(CTParagraphStyleSetting(
                spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tabPointer
            ))
        }
        return CTParagraphStyleCreate(settings, settings.count)
    }

    /// `NSString.getParagraphStart`·CoreText의 문단 구분자 — LF·CR·U+2029 (CRLF는 둘의
    /// 연속). U+2028·U+0085는 줄 구분자라 문단 스타일이 다시 걸리지 않는다.
    private static func isParagraphSeparator(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2029
    }

    /// 조각 안 첫 CT 문단의 끝(구분자 포함) — 구분자가 없으면 조각 길이. 조각만
    /// 훑으므로 비용이 조각 길이에 비례한다.
    private static func firstParagraphEnd(in fragment: NSString) -> Int {
        var index = 0
        while index < fragment.length {
            let unit = fragment.character(at: index)
            index += 1
            if unit == 0x0D, index < fragment.length, fragment.character(at: index) == 0x0A {
                return index + 1
            }
            if isParagraphSeparator(unit) {
                return index
            }
        }
        return fragment.length
    }

    private static func allocated<T>(_ value: T) -> UnsafeMutablePointer<T> {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        pointer.initialize(to: value)
        return pointer
    }

    private static func floatValue(
        _ specifier: CTParagraphStyleSpecifier, of style: CTParagraphStyle
    ) -> CGFloat {
        var value: CGFloat = 0
        CTParagraphStyleGetValueForSpecifier(style, specifier, MemoryLayout<CGFloat>.size, &value)
        return value
    }
}
