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
    /// 바꾸는 범위는 조각의 **첫 CT 문단**(첫 한 줄 끝 `\n`까지)뿐이다 — 한 줄
    /// 끝(코드 10) 뒤는 측정에서도 CT 문단이 새로 시작해 `firstLineHeadIndent`에
    /// 놓이므로 원래 스타일을 유지해야 줄바꿈이 같다. 같은 이유로 조각이 한 줄 끝
    /// 바로 뒤에서 시작하면 첫 줄도 원래대로 둔다. 문단 첫머리 조각, 두 들여쓰기가
    /// 같은 문단, 스타일 없는 문자열은 그대로 잘라 돌려준다.
    static func continuationFragment(
        of attributedString: NSAttributedString, range: NSRange
    ) -> NSAttributedString {
        let fragment = attributedString.attributedSubstring(from: range)
        let string = attributedString.string as NSString
        guard range.location > 0, fragment.length > 0,
              string.character(at: range.location - 1) != 0x0A,
              let value = fragment.attribute(
                  kCTParagraphStyleAttributeName as NSAttributedString.Key, at: 0,
                  effectiveRange: nil
              ), CFGetTypeID(value as CFTypeRef) == CTParagraphStyleGetTypeID()
        else { return fragment }
        let style = value as! CTParagraphStyle // swiftlint:disable:this force_cast
        let firstLine = floatValue(.firstLineHeadIndent, of: style)
        let head = floatValue(.headIndent, of: style)
        guard abs(firstLine - head) > 0.001 else { return fragment }

        let lineBreak = (fragment.string as NSString).range(of: "\n")
        let firstParagraphLength = lineBreak.location == NSNotFound
            ? fragment.length : lineBreak.location + lineBreak.length
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
