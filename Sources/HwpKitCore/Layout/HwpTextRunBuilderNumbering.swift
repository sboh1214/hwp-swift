import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// HwpTextRunBuilder의 문단 번호·개요 번호 라벨 전치 (#154)

extension HwpTextRunBuilder {
    /// 문단 머리를 조판 문자열 앞에 전치한다 — 글머리표(표 44 heading 3)는
    /// `appendBulletHeading`, 개요(1)·번호 매기기(2)는 `HwpParagraphNumbering`이
    /// 문서 순서로 만든 번호(`number`)의 라벨이다. `number`가 없으면(번호 문단이
    /// 아니거나 조판기가 경로를 나르지 않는 컨테이너 문단) 글머리표만 본다.
    func appendParagraphHeading(
        for paragraph: CoreHwp.HwpParagraph,
        number: HwpParagraphNumber?,
        to output: NSMutableAttributedString
    ) {
        guard let number else {
            appendBulletHeading(for: paragraph, to: output)
            return
        }
        appendNumberingHeading(for: paragraph, number: number, to: output)
    }

    /// 번호 라벨 전치: `라벨 [뒤 여백 + 본문과의 거리]` (#154). 앞 여백(가운데·오른쪽
    /// 정렬)은 글자가 아니라 첫 줄 들여쓰기 표식(`numberingFirstLineInset`)이다.
    ///
    /// 표 39 문단 머리 정보(`HwpParaHeadInfo`)의 해석은 한컴 도움말(개요 번호 모양
    /// 대화상자)의 정의를 따른다.
    /// - **글자 모양**: 정의의 `charShapeId`가 실재하면 그 모양, -1이면 "개요 번호의
    ///   글자 모양은 개요 문단의 맨 마지막 글자의 글자 모양을 따라갑니다"
    ///   (`paraCharShape`의 마지막 run). 스펙 주석의 "바탕글"이 아니다 — 헌법주석
    ///   개요 1,944문단은 바탕글(휴먼명조 10pt)과 달리 수준별 굵은 글꼴이라 두
    ///   해석이 눈에 띄게 갈린다.
    /// - **번호 너비**(`useInstWidth`·`widthAdjust`): 자릿수에 맞추면 라벨의 실제
    ///   폭 + 너비 보정값, 아니면 **글자 크기 × `HwpRenderTuning.Numbering.
    ///   fixedWidthEmRatio`(1.5) + 너비 보정값**(라벨이 더 넓으면 라벨 폭) — 실측
    ///   근거는 그 상수의 doc-comment.
    /// - **정렬**(`alignment`): 번호 너비 안에서 라벨을 왼쪽·가운데·오른쪽에 둔다 —
    ///   라벨 뒤 남은 폭은 거리 빈칸의 kern에, 앞 남은 폭은 첫 줄 들여쓰기에 더한다.
    /// - **본문과의 거리**(`textOffsetType`·`textOffset`): 비율이면 라벨 글자
    ///   크기의 %, HWPUNIT이면 절대값. 거리는 라벨 글자 모양의 빈칸 한 자로 낸다 —
    ///   한글.app도 복사 텍스트에 `1. `처럼 빈칸을 넣는다(문단 경계 복사 실측).
    /// - **자동 내어쓰기**(`autoIndent`): 라벨 폭 + 뒤 여백 + 거리를
    ///   `HwpAttributedStringKey.numberingHeadIndent`로 실어 둘째 줄부터를 첫 줄
    ///   본문 시작에 맞춘다(`HwpParagraphLayout.ParagraphMetrics` — 앞 여백은 첫 줄
    ///   들여쓰기에 이미 들어 있다).
    ///
    /// 라벨과 여백 전체에 `HwpAttributedStringKey.numberingLabel` 표식을 단다.
    /// 라벨이 빈 문자열이면(형식 슬롯 없음) 아무것도 전치하지 않는다.
    func appendNumberingHeading(
        for paragraph: CoreHwp.HwpParagraph,
        number: HwpParagraphNumber,
        to output: NSMutableAttributedString
    ) {
        guard !number.text.isEmpty else { return }
        let info = index.numbering(id: number.definitionIndex)?
            .format(forLevel: number.level)?.paraHeadInfo
        let shapeId = numberingHeadingShapeId(info: info, paragraph: paragraph)

        // 라벨 글자는 본문과 같은 chunk 경로로 **글자마다** 낸다 — `accumulate`는 호출
        // 단위로 첫 스칼라의 스크립트를 판정하므로 `(나)`를 통째로 넘기면 `(`의 영문
        // 슬롯이 `나`까지 덮는다. 글자마다 넘겨야 스크립트 전환에서 chunk가 갈리고
        // 슬롯별 폰트·상대 크기·장평·자간·장식이 본문 글자와 같은 규칙을 따른다.
        let label = NSMutableAttributedString()
        var chunk = Chunk(shapeId: shapeId, script: nil)
        for character in number.text {
            accumulate(
                String(character), shapeId: shapeId, into: &chunk, paragraph: paragraph, to: label
            )
        }
        append(chunk, paragraph: paragraph, to: label)
        guard label.length > 0 else { return }

        // 거리 빈칸은 본문 빈칸(U+0020 → `.english`)과 같은 슬롯이다.
        let spaceAttributes = attributes(
            for: resolvedShape(id: shapeId, paragraph: paragraph), script: .english
        )
        guard let fontValue = spaceAttributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
        else {
            output.append(label)
            return
        }
        let font = fontValue as! CTFont // swiftlint:disable:this force_cast
        let metrics = NumberingHeadingMetrics(
            info: info,
            labelWidth: Self.typographicWidth(of: label),
            fontSize: CTFontGetSize(font)
        )

        let start = output.length
        output.append(label)
        output.append(Self.paddingSpace(
            width: max(0, metrics.trailingPad + metrics.gap), font: font,
            attributes: spaceAttributes
        ))
        Self.markNumberingLabel(
            in: output, from: start, metrics: metrics, autoIndent: info?.autoIndent ?? false
        )
    }

    /// `start`부터 끝까지를 라벨 범위로 표식한다 — 표식 자체, 정렬 앞 여백(첫 줄
    /// 들여쓰기), 자동 내어쓰기 전진량.
    static func markNumberingLabel(
        in output: NSMutableAttributedString,
        from start: Int,
        metrics: NumberingHeadingMetrics,
        autoIndent: Bool
    ) {
        let range = NSRange(location: start, length: output.length - start)
        output.addAttribute(
            HwpAttributedStringKey.numberingLabel, value: NSNumber(value: true), range: range
        )
        if metrics.leadingPad > 0 {
            output.addAttribute(
                HwpAttributedStringKey.numberingFirstLineInset,
                value: NSNumber(value: Double(metrics.leadingPad)),
                range: range
            )
        }
        if autoIndent {
            output.addAttribute(
                HwpAttributedStringKey.numberingHeadIndent,
                value: NSNumber(value: Double(metrics.headIndent)),
                range: range
            )
        }
    }

    /// 라벨의 글자 모양 id — 정의의 `charShapeId`가 사전에 실재하면 그것, 아니면
    /// (-1 또는 없는 id) 문단 맨 마지막 글자의 글자 모양(한컴 도움말). 글머리표
    /// (`appendBulletHeading`)는 첫 글자 모양을 쓰지만 개요 번호의 규칙은 마지막이다.
    func numberingHeadingShapeId(
        info: CoreHwp.HwpParaHeadInfo?,
        paragraph: CoreHwp.HwpParagraph
    ) -> UInt32 {
        if let id = info?.charShapeId, id >= 0, index.charShape(id: UInt32(id)) != nil {
            return UInt32(id)
        }
        return paragraph.paraCharShape.shapeId.last ?? 0
    }

    /// 폭 `width`의 빈칸 한 자 — 글리프 advance와의 차를 kern으로 메운다. 빈칸을
    /// 쓰는 이유는 복사 텍스트에 한글.app과 같은 구분 빈칸이 들어가게 하기
    /// 위해서다. `applyFixedSpaceWidth`의 0.5em 규칙은 `append`를 거치지 않으므로
    /// 여기 kern이 유일한 폭 근거다.
    static func paddingSpace(
        width: CGFloat,
        font: CTFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var spaceAttributes = attributes
        spaceAttributes[kCTKernAttributeName as NSAttributedString.Key] = NSNumber(
            value: Double(width - glyphAdvance(of: 0x20, in: font))
        )
        return NSAttributedString(string: " ", attributes: spaceAttributes)
    }

    /// 문자 하나의 가로 advance (pt) — 글리프가 없으면 0.
    static func glyphAdvance(of character: UniChar, in font: CTFont) -> CGFloat {
        var character = character
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }

    /// 조판 문자열 한 줄의 타이포그래픽 폭 (pt).
    static func typographicWidth(of attributedString: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

extension HwpTextRunBuilder {
    /// 표 39 문단 머리 정보로 푼 라벨 기하 (pt) — 순수 값이라 합성 테스트가 정의
    /// 없이도 잠근다.
    struct NumberingHeadingMetrics: Equatable {
        /// 번호 너비 안에서 라벨 왼쪽에 남는 폭 (정렬 가운데·오른쪽).
        let leadingPad: CGFloat
        /// 번호 너비 안에서 라벨 오른쪽에 남는 폭 — 너비 보정값이 음수면 음수라
        /// 거리를 그만큼 깎는다.
        let trailingPad: CGFloat
        /// 본문과의 거리.
        let gap: CGFloat
        /// 자동 내어쓰기 전진량 — 라벨 + 뒤 여백 + 거리. 앞 여백은 첫 줄 들여쓰기에
        /// 이미 들어가므로 여기서 다시 세지 않는다.
        let headIndent: CGFloat

        /// - Parameters:
        ///   - info: 문단 머리 정보 — nil이면 한글 기본값(왼쪽·자릿수 맞춤·비율 50%).
        ///   - labelWidth: 라벨 글자의 타이포그래픽 폭.
        ///   - fontSize: 라벨 글자 크기 — 비율 거리와 고정 번호 너비의 기준.
        init(info: CoreHwp.HwpParaHeadInfo?, labelWidth: CGFloat, fontSize: CGFloat) {
            let adjust = info.map { HwpUnits.points(fromHwpUnit16: $0.widthAdjust) } ?? 0
            let boxWidth = (info?.useInstWidth ?? true)
                ? labelWidth + adjust
                : max(labelWidth, fontSize * HwpRenderTuning.Numbering.fixedWidthEmRatio + adjust)
            let slack = boxWidth - labelWidth
            let positive = max(0, slack)
            switch info?.alignment ?? .left {
            case .left:
                leadingPad = 0
                trailingPad = slack
            case .center:
                leadingPad = positive / 2
                trailingPad = slack - positive / 2
            case .right:
                leadingPad = positive
                trailingPad = slack - positive
            }
            gap = switch info?.textOffsetType {
            case .hwpUnit: HwpUnits.points(fromHwpUnit16: info?.textOffset ?? 0)
            case .percent, nil: fontSize * CGFloat(info?.textOffset ?? 50) / 100
            }
            headIndent = max(0, labelWidth + trailingPad + gap)
        }
    }
}
