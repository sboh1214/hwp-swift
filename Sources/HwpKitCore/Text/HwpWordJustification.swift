import CoreGraphics
import CoreText
import Foundation

/// 양쪽 정렬의 한글식 재조판: 남는 폭을 공백에만 배분한다.
///
/// CoreText의 기본 justification은 남는 폭을 글자 사이에도 배분해 좁은 단에서
/// "a m e t ,"처럼 자간이 벌어진다. 한글은 단어 간격(공백) 위주로 늘린다
/// (Column 픽스처 PrvImage 실측 — 한 칸 공백이 10배 이상 벌어짐).
/// 공백이 없는 줄(CJK 연속 run 등)과 문단 마지막 줄은 CT 기본 조판을 유지한다 — 단 공백
/// 없는 줄의 마지막 글자 자간을 CoreText가 줄 폭에 넣고 맞췄으면 그 자간을 뺀 폭으로 CoreText
/// 정렬을 다시 건다 (#260, `lineEndSpacingJustified`).
public enum HwpWordJustification {
    /// frameLine이 양쪽 정렬 대상 줄이면 공백 kern으로 재조판한 CTLine을 준다.
    /// 대상이 아니면 (마지막 줄/정렬 아님, 공백이 없고 줄 끝 자간도 없는 줄) nil — 호출자가
    /// 원본을 그린다. 공백 없는 줄은 줄 끝 자간이 있을 때 그 몫만큼 좁게 다시 맞춘 줄이다.
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
        let isLastLine = isParagraphLastLine(
            lineEnd: lineEnd, string: string, attributedString: attributedString
        )
        if !distributes, isLastLine {
            return nil
        }
        guard let style = paragraphStyle(of: attributedString, at: nsRange.location),
              alignment(of: style) == .justified
        else { return nil }
        let targetWidth = targetWidth(style: style, availableWidth: availableWidth)
        guard targetWidth > 1 else { return nil }

        // 뒤쪽 공백을 제외한 본문 범위에서 늘릴 공백 위치를 모은다. 문단 번호
        // 라벨의 거리 빈칸(`numberingLabel` 표식, #154)은 단어 간격이 아니라 정의가
        // 정한 거리라 늘리지 않는다 — 늘리면 첫 줄 본문 시작이 자동 내어쓰기로 맞춘
        // 둘째 줄보다 오른쪽으로 튄다.
        let substring = attributedString.attributedSubstring(from: nsRange)
        let (spaceOffsets, excludedLabelSpaces) = stretchableSpaceOffsets(
            in: string, range: nsRange, attributedString: attributedString
        )
        // 늘릴 곳: 단어 간격이 있으면 빈칸, 라벨 빈칸뿐이면 본문 글자 사이 (CT의
        // 프레임 정렬은 라벨 빈칸까지 늘리므로 한글처럼 글자 사이만 균등하게
        // 벌린다). 라벨도 빈칸도 없는 줄은 CT 기본 정렬이되, 마지막 글자 자간만큼 좁게 다시
        // 맞춘다 (`lineEndSpacingJustified` — 줄 끝 자간이 없으면 CT 프레임 줄 그대로).
        let stretchRanges: [NSRange]
        if spaceOffsets.isEmpty {
            guard excludedLabelSpaces else {
                return isLastLine ? nil : lineEndSpacingJustified(substring, targetWidth: targetWidth)
            }
            stretchRanges = interCharacterRanges(in: substring)
            guard !stretchRanges.isEmpty else {
                return (line: CTLineCreateWithAttributedString(substring), xOffset: 0)
            }
        } else {
            stretchRanges = spaceOffsets.map { NSRange(location: $0, length: 1) }
        }

        // 자연 폭 (문단 스타일 정렬은 CTLine 단독 조판에 적용되지 않는다)
        // 줄의 마지막 글자는 자간을 받지 않는다 (#260) — CoreText가 줄 폭에 넣고 잰 그 자간
        // (`lineEndExcess`: 음수, 컨트롤 표식에 막혀 안 매달린 양수)을 뺀다. 안 빼면 그 자간만큼 더
        // 벌려 마지막 글자가 오른쪽 끝을 넘는다 (noori 양쪽 정렬 줄: 한글은 마지막 글자 + 자간 없는
        // 전진량 = 오른쪽 끝). 재는 문자열은 이 줄의 부분 문자열이다 — 다시 그리는 줄이 그것이라,
        // 문단이 CoreText 자간 상한(`coreTextSpacingLengthLimit`)보다 길어도 이 줄에는 자간이 실린다.
        let naturalLine = CTLineCreateWithAttributedString(substring)
        let excess = HwpLetterSpacing.lineEndExcess(
            in: substring, range: NSRange(location: 0, length: substring.length)
        )
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(naturalLine, nil, nil, nil))
            - CGFloat(CTLineGetTrailingWhitespaceWidth(naturalLine)) - excess
        let extra = targetWidth - naturalWidth
        // 남는 폭이 작으면(≤ 0.25pt) CoreText 프레임 줄을 그대로 그리는데, 줄 끝 자간이 있으면 안
        // 된다 — 프레임 줄은 그 자간을 넣은 폭을 끝에 맞춰 마지막 글자가 자간만큼 넘친다 (#260 리뷰
        // 실측: Menlo 12pt −20% 줄의 1.2–1.7%가 정확히 |자간|만큼 넘쳤다). 그때는 작은 여분이라도 빈칸에
        // 나눈다 (줄바꿈 코어가 자간을 빼고 재면 들어가게 나눴으므로 여분은 0 이상이다).
        guard extra > 0.25 || (excess != 0 && extra > -0.001) else { return nil }

        let kernPerSpace = distributes
            ? extra / CGFloat(stretchRanges.count + 1)
            : extra / CGFloat(stretchRanges.count)
        let mutable = NSMutableAttributedString(attributedString: substring)
        let kernKey = kCTKernAttributeName as NSAttributedString.Key
        let trackingKey = kCTTrackingAttributeName as NSAttributedString.Key
        for range in stretchRanges {
            // 기존 kern (고정 공백 폭 보정)에 가산 — 교체하면 배분이 기존
            // kern 합만큼 상쇄되어 양쪽 정렬이 무효가 된다 (CCL 실측). 자간을 tracking으로 실은
            // 글자(#260)는 CoreText가 kern을 무시하므로 tracking에 더한다.
            let key = mutable.attribute(trackingKey, at: range.location, effectiveRange: nil) != nil
                ? trackingKey : kernKey
            let existing = (mutable.attribute(key, at: range.location, effectiveRange: nil)
                as? NSNumber)?.doubleValue ?? 0
            mutable.addAttribute(
                key, value: NSNumber(value: existing + Double(kernPerSpace)), range: range
            )
        }
        return (
            line: CTLineCreateWithAttributedString(mutable),
            xOffset: distributes ? kernPerSpace / 2 : 0
        )
    }

    /// 늘릴 빈칸이 없는 줄 — CoreText가 프레임에서 글자 사이로 벌리는데, 마지막 글자의 음수 자간을 넣고
    /// 폭을 맞추므로 마지막 글자가 오른쪽 끝을 그 자간만큼 넘는다 (#260, 실측: Apple SD 산돌고딕 Neo
    /// 20pt 한글 자간 −3.46pt 줄을 200pt에 맞추면 마지막 글자 끝이 203.46pt). 한글은 마지막 글자에 자간을
    /// 주지 않으므로 그 자간만큼 좁은 폭으로 다시 벌린다 (컨트롤 표식에 막혀 매달리지 않은 양수 자간이면
    /// 그만큼 넓게). CoreText가 줄 폭에 넣은 줄 끝 자간(`HwpLetterSpacing.lineEndExcess`)이 없거나 이미
    /// 넘치는 줄은 nil — CoreText의 줄 그대로다.
    private static func lineEndSpacingJustified(
        _ substring: NSAttributedString, targetWidth: CGFloat
    ) -> (line: CTLine, xOffset: CGFloat)? {
        let spacing = HwpLetterSpacing.lineEndExcess(
            in: substring, range: NSRange(location: 0, length: substring.length)
        )
        guard spacing != 0 else { return nil }
        let line = CTLineCreateWithAttributedString(substring)
        let width = targetWidth + spacing
        let content = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        guard width > content, let justified = CTLineCreateJustifiedLine(line, 1, Double(width))
        else { return nil }
        return (line: justified, xOffset: 0)
    }

    /// 라벨 빈칸만 있는 줄의 글자 사이 벌림 자리 — 라벨 범위(`numberingLabel`)와
    /// 뒤쪽 공백을 뺀 본문의 글자(결합 문자 단위)마다 그 범위, 마지막 글자는 제외
    /// (마지막 글자 뒤 kern은 줄 폭 밖으로 나간다).
    private static func interCharacterRanges(in substring: NSAttributedString) -> [NSRange] {
        let string = substring.string as NSString
        var contentLength = substring.length
        while contentLength > 0, isStretchableSpace(string.character(at: contentLength - 1)) {
            contentLength -= 1
        }
        var ranges: [NSRange] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: contentLength),
            options: [.byComposedCharacterSequences, .substringNotRequired]
        ) { _, range, _, _ in
            guard substring.attribute(
                HwpAttributedStringKey.numberingLabel, at: range.location, effectiveRange: nil
            ) == nil else { return }
            ranges.append(range)
        }
        return Array(ranges.dropLast())
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

    /// 뒤쪽 공백을 제외한 줄 본문에서 늘릴 공백의 줄-내 오프셋 목록과, 라벨 빈칸을
    /// 제외했는지.
    private static func stretchableSpaceOffsets(
        in string: NSString,
        range: NSRange,
        attributedString: NSAttributedString
    ) -> (offsets: [Int], excludedLabelSpaces: Bool) {
        var contentLength = range.length
        while contentLength > 0,
              isStretchableSpace(string.character(at: range.location + contentLength - 1))
        {
            contentLength -= 1
        }
        var offsets: [Int] = []
        var excluded = false
        for offset in 0 ..< contentLength
            where isStretchableSpace(string.character(at: range.location + offset))
        {
            if attributedString.attribute(
                HwpAttributedStringKey.numberingLabel, at: range.location + offset,
                effectiveRange: nil
            ) != nil {
                excluded = true
                continue
            }
            offsets.append(offset)
        }
        return (offsets, excluded)
    }

    /// 늘릴 수 있는 공백: U+0020 (한글 문서의 단어 간격)
    private static func isStretchableSpace(_ unit: unichar) -> Bool {
        unit == 0x20
    }
}
