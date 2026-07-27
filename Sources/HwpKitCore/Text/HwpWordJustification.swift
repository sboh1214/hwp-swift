import CoreGraphics
import CoreText
import Foundation

/// 양쪽 정렬의 한글식 재조판: 남는 폭을 공백에만 배분한다.
///
/// CoreText의 기본 justification은 남는 폭을 글자 사이에도 배분해 좁은 단에서
/// "a m e t ,"처럼 자간이 벌어진다. 한글은 단어 간격(공백) 위주로 늘린다
/// (Column 픽스처 PrvImage 실측 — 한 칸 공백이 10배 이상 벌어짐).
/// 공백이 없는 줄(CJK 연속 run 등)과 문단 마지막 줄은 CT 기본 조판을 유지한다.
public enum HwpWordJustification {
    /// frameLine이 양쪽 정렬 대상 줄이면 공백 kern으로 재조판한 CTLine을 준다.
    /// 대상이 아니면 (마지막 줄/공백 없음/정렬 아님) nil — 호출자가 원본을 그린다.
    public static func wordJustifiedLine(
        frameLine: CTLine,
        attributedString: NSAttributedString,
        availableWidth: CGFloat
    ) -> CTLine? {
        justifiedLine(
            frameLine: frameLine,
            attributedString: attributedString,
            availableWidth: availableWidth
        )?.line
    }

    /// wordJustifiedLine + 시작 x 이동량. 배분/나눔 정렬은 여분을 (공백 수
    /// + 1)로 나눠 양끝에도 절반씩 남긴다 (noori 글상자 실물: 배분 줄
    /// 양끝 대시가 음영 안쪽 ~1% 지점).
    public static func justifiedLine(
        frameLine: CTLine,
        attributedString: NSAttributedString,
        availableWidth: CGFloat
    ) -> (line: CTLine, xOffset: CGFloat)? {
        let range = CTLineGetStringRange(frameLine)
        guard range.length > 0, availableWidth > 1 else { return nil }
        let nsRange = NSRange(location: range.location, length: range.length)
        let string = attributedString.string as NSString
        let lineEnd = nsRange.location + nsRange.length

        // 배분/나눔 정렬은 마지막 줄도 벌린다 (공공누리 실물 실측);
        // 양쪽 정렬은 마지막 줄 (문자열 끝/개행으로 끝나는 줄)을 건너뛴다
        let distributes = attributedString.attribute(
            HwpAttributedStringKey.distributeAlignment,
            at: nsRange.location,
            effectiveRange: nil
        ) != nil
        if !distributes, isParagraphLastLine(
            lineEnd: lineEnd, string: string, attributedString: attributedString
        ) {
            return nil
        }
        guard let style = paragraphStyle(of: attributedString, at: nsRange.location),
              alignment(of: style) == .justified
        else { return nil }
        let targetWidth = targetWidth(style: style, availableWidth: availableWidth)
        guard targetWidth > 1 else { return nil }

        // 뒤쪽 공백을 제외한 본문 범위에서 늘릴 공백 위치를 모은다
        let spaceOffsets = stretchableSpaceOffsets(in: string, range: nsRange)
        guard !spaceOffsets.isEmpty else { return nil }

        // 자연 폭 (문단 스타일 정렬은 CTLine 단독 조판에 적용되지 않는다)
        let substring = attributedString.attributedSubstring(from: nsRange)
        let naturalLine = CTLineCreateWithAttributedString(substring)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(naturalLine, nil, nil, nil))
            - CGFloat(CTLineGetTrailingWhitespaceWidth(naturalLine))
        let extra = targetWidth - naturalWidth
        guard extra > 0.25 else { return nil }

        let kernPerSpace = distributes
            ? extra / CGFloat(spaceOffsets.count + 1)
            : extra / CGFloat(spaceOffsets.count)
        let mutable = NSMutableAttributedString(attributedString: substring)
        let kernKey = kCTKernAttributeName as NSAttributedString.Key
        for offset in spaceOffsets {
            // 기존 kern (고정 공백 폭 보정)에 가산 — 교체하면 배분이 기존
            // kern 합만큼 상쇄되어 양쪽 정렬이 무효가 된다 (CCL 실측)
            let existing = (mutable.attribute(kernKey, at: offset, effectiveRange: nil)
                as? NSNumber)?.doubleValue ?? 0
            mutable.addAttribute(
                kernKey,
                value: NSNumber(value: existing + Double(kernPerSpace)),
                range: NSRange(location: offset, length: 1)
            )
        }
        return (
            line: CTLineCreateWithAttributedString(mutable),
            xOffset: distributes ? kernPerSpace / 2 : 0
        )
    }

    /// 오른쪽 여백 (tailIndent ≤ 0 = 오른쪽 끝에서의 오프셋)만큼 줄 폭을 줄인다
    private static func targetWidth(
        style: CTParagraphStyle,
        availableWidth: CGFloat
    ) -> CGFloat {
        var tailIndent: CGFloat = 0
        CTParagraphStyleGetValueForSpecifier(
            style,
            .tailIndent,
            MemoryLayout<CGFloat>.size,
            &tailIndent
        )
        return tailIndent <= 0 ? availableWidth + tailIndent : availableWidth
    }

    /// 문단 마지막 줄 (양쪽 정렬 제외 대상) 판정: 개행으로 끝나는 줄, 또는
    /// 조각의 끝 줄 — 단 문단이 다음 단/쪽으로 이어지는 조각의 끝 줄은
    /// 마지막 줄이 아니다 (Column 실물: 단 경계 직전 줄도 벌린다)
    private static func isParagraphLastLine(
        lineEnd: Int,
        string: NSString,
        attributedString: NSAttributedString
    ) -> Bool {
        if string.character(at: lineEnd - 1) == 0x0A {
            return true
        }
        guard lineEnd >= string.length else { return false }
        let continued = attributedString.attribute(
            HwpAttributedStringKey.continuedParagraphFragment,
            at: string.length - 1,
            effectiveRange: nil
        ) != nil
        return !continued
    }

    private static func paragraphStyle(
        of attributed: NSAttributedString,
        at location: Int
    ) -> CTParagraphStyle? {
        guard let value = attributed.attribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            at: location,
            effectiveRange: nil
        ), CFGetTypeID(value as CFTypeRef) == CTParagraphStyleGetTypeID() else { return nil }
        return (value as! CTParagraphStyle) // swiftlint:disable:this force_cast
    }

    private static func alignment(of style: CTParagraphStyle) -> CTTextAlignment {
        var alignment = CTTextAlignment.natural
        CTParagraphStyleGetValueForSpecifier(
            style,
            .alignment,
            MemoryLayout<CTTextAlignment>.size,
            &alignment
        )
        return alignment
    }

    /// 뒤쪽 공백을 제외한 줄 본문에서 늘릴 공백의 줄-내 오프셋 목록
    private static func stretchableSpaceOffsets(
        in string: NSString,
        range: NSRange
    ) -> [Int] {
        var contentLength = range.length
        while contentLength > 0,
              isStretchableSpace(string.character(at: range.location + contentLength - 1))
        {
            contentLength -= 1
        }
        var offsets: [Int] = []
        for offset in 0 ..< contentLength
            where isStretchableSpace(string.character(at: range.location + offset))
        {
            offsets.append(offset)
        }
        return offsets
    }

    /// 늘릴 수 있는 공백: U+0020 (한글 문서의 단어 간격)
    private static func isStretchableSpace(_ unit: unichar) -> Bool {
        unit == 0x20
    }
}
