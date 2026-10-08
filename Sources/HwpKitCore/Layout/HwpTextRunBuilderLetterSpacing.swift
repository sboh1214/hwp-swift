import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 글자 모양 자간(표 33 `faceSpacing`)을 **글자마다 그 글자의 전진량에 비례해** 싣는다 (#260).
///
/// 한글은 자간을 글자 크기의 %가 아니라 **그 글자의 전진량**(상대 크기·장평을 적용한 뒤, 자간을
/// 더하기 전)의 %로 더한다 — 한컴오피스 한글 12.30.0 build 6523 실측(2026-10-08, 합성 HWPX 20pt를
/// PDF로 내보내 글자 원점 사이 거리를 읽었다, 600dpi 장치 단위 0.12pt 양자화, `probes/260`):
/// - 함초롬바탕 `a`(11.40pt)에 라틴 자간 +20%면 13.68pt, −20%면 9.12pt다 — 글자 크기의 %라면 15.40·
///   7.40pt다. ±30·±50%(최대)도 같은 비례이고(`i` 5.76pt → +50% 8.64·−50% 2.88pt), 한글·한자·일어·
///   기호 항목도 같다(`가` 19.44pt → +20% 23.28pt).
/// - **기준은 장평 적용 뒤의 전진량이다**: 라틴 장평 50%·자간 +20%의 `a`는 5.70 × 1.2 = 6.84pt
///   (장평 적용 전 전진량의 %면 7.98pt)이고 장평 80·150·200%도 같다. 상대 크기도 적용 뒤다
///   (상대 크기 50%·자간 +20%의 `a` 6.72–6.84pt).
/// - 폭 0 글자는 자간도 0이다 — 결합 부호(`e` + U+0301)·U+200B는 자리를 차지하지 않고 앞 글자만
///   자간을 받는다. 대리 쌍 글자(U+1D400, 한자 확장 B)는 한 글자로 자기 전진량의 %를 받는다.
/// - 글꼴의 짝 커닝은 쓰지 않는다 — Times New Roman `AVAW`가 커닝 없는 전진량 × 1.2다.
/// - MS 워드 호환·한글 2007 호환 문서도 같은 규칙이다.
///
/// **값을 싣는 CoreText 속성은 글자마다 고른다** (`Carrier`) — 둘 다 글자 묶음마다 한 번 더해지는
/// 가산이지만(함초롬·Apple SD 산돌고딕 Neo·Menlo·Times·SF·이모지·수학 글꼴, 결합 부호·대리 쌍·이모지
/// 변이 선택자 묶음까지 실측으로 같다) 둘이 갈리는 자리가 셋이다:
/// - **짝 커닝**: CoreText는 kern이 **정확히 0**인 글자에서 커닝을 끄고 0이 아니면 켠다 — 이웃한 두
///   글자가 모두 kern ≠ 0이면 짝 커닝이 걸린다 (실측: Times New Roman 20pt `AV`가 kern 0에서 14.44pt,
///   kern 2에서 13.87pt). 한글은 짝 커닝을 쓰지 않으므로 커닝에 관여할 수 있는 글리프
///   (`HwpKerningCoverage`)의 자간은 kern 0 + tracking으로 싣는다 (`AVAWaw` +20%를 kern에 실으면
///   한글보다 8.4pt 좁았다).
/// - **양수의 줄 끝**: CoreText는 줄의 마지막 글자에 실린 양수 tracking을 줄 끝 공백처럼 빼고
///   재는데(`CTLineGetTrailingWhitespaceWidth`가 그 몫을 낸다), 양수 kern은 넣고 잰다(실측: Menlo
///   20pt 자간 +2.4pt `aaaaa` 줄 나눔 경계가 tracking 322.6pt, kern 325.0pt). 한글도 줄의 마지막
///   글자에는 자간을 주지 않으므로 **양수 자간은 tracking**이다. 음수는 둘 다 넣고 잰다(줄 나눔 경계·
///   줄 폭 실측 같음) — 그 몫은 줄바꿈 코어가 뺀다 (`HwpLineBreaker`의 줄 끝 자간 생략).
/// - **속도**: tracking run은 CoreText 조판(`CTTypesetterCreate`)이 kern run보다 약 3배, 글자마다 값이
///   다른 라틴 글자열은 약 7배 느리다(실측: 2,300자 문단 20회 kern 51ms·tracking 127ms·글자마다 tracking
///   411ms). 자간을 전부 tracking에 실으면 1,030쪽 헌법주석 로드가 기본 글꼴 모드에서 20.4초 → 27.7초
///   였다. 그래서 **음수 자간은 커닝에 관여하지 않는 글리프면 kern**이다 — 한글 음절·한자는 한글
///   글꼴의 커닝 집합에 거의 들지 않는다(예외와 실측은 `HwpKerningCoverage`).
///
/// 빈칸은 이 규칙이 아니다 — 빈칸 폭 패스(`applySpaceWidths`)가 kern으로 폭을 준다
/// (`HwpSpaceWidthMetrics`). tracking이 (0이라도) 붙은 글자는 CoreText가 그 글자의 kern을 무시하므로
/// 자간이 0인 묶음(빈칸·폭 0 글자)에는 tracking을 달지 않는다.
extension HwpTextRunBuilder {
    /// chunk 한 조각을 자간을 실은 조판 문자열로 — 자간이 0이거나 글꼴이 없으면 `attributes` 그대로.
    ///
    /// 글자 묶음(`rangeOfComposedCharacterSequence`)마다 한 값이고, 같은 값·같은 운반 속성이 이어지는
    /// 묶음은 한 범위로 쓴다 — 한글 음절처럼 전진량이 같은 글자는 run을 쪼개지 않는다. 묶음 **안**에
    /// 경계를 두지 않는다: 대리 쌍 사이에 속성 경계가 생기면 CoreText가 두 반쪽을 따로 그려 글리프가
    /// 깨지고(LastResort), 결합 부호를 기저와 다른 값으로 나누면 부호가 기저에서 떨어진다.
    ///
    /// 자간 표식(`HwpAttributedStringKey.letterSpacing`, 자간 비율)은 chunk 기본 사전에 한 번만 싣고
    /// 묶음마다는 운반 속성 하나만 더한다 — 묶음마다 속성 사전을 둘 이상 고치면 조판 문자열 생성·속성
    /// 열거가 그만큼 느려진다(1,030쪽 헌법주석 로드 실측). 묶음이 하나뿐인 chunk(한글 낱말)는 가변
    /// 문자열을 거치지 않는다. `preceding`은 첫 묶음이 kern 후보일 때만 부른다. `cache`는 대체 글꼴·커닝
    /// 집합 조회를 문서 안에서 한 번만 하게 한다. `coverage`는 커닝 집합을 바꿔 끼우는 테스트 이음매다.
    static func letterSpacedString(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        ratio: CGFloat,
        preceding: () -> HwpLetterSpacing.Preceding? = { nil },
        cache: HwpTextAttributeCache? = nil,
        coverage: ((CTFont) -> HwpKerningCoverage.GlyphSet?)? = nil
    ) -> NSAttributedString {
        guard ratio != 0,
              let fontValue = attributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
        else { return NSAttributedString(string: text, attributes: attributes) }
        let font = unsafeBitCast(fontValue as CFTypeRef, to: CTFont.self)
        let segments = HwpLetterSpacing.segments(
            of: text as NSString, font: font, ratio: ratio, preceding: preceding, cache: cache,
            coverage: coverage ?? { font in
                // 캐시가 nil(전체 글리프)을 돌려주는 글꼴을 다시 해석하지 않는다 — `??`로 이으면 그 글꼴만
                // 매 chunk 해석 경로를 탄다.
                if let cache {
                    return cache.kerningCoverage(of: font)
                }
                return HwpKerningCoverage.glyphs(of: font)
            }
        )
        var base = attributes
        // kern 0이 기본이다 — 0이어야 짝 커닝이 꺼진다(자간이 없는 글자·tracking 글자).
        base[kCTKernAttributeName as NSAttributedString.Key] = NSNumber(value: 0)
        base[HwpAttributedStringKey.letterSpacing] = NSNumber(value: Double(ratio))
        if segments.count == 1, let only = segments.first {
            if only.spacing != 0 {
                base[only.carrier.key] = NSNumber(value: Double(only.spacing))
            }
            return NSAttributedString(string: text, attributes: base)
        }
        let output = NSMutableAttributedString(string: text, attributes: base)
        for segment in segments where segment.spacing != 0 {
            let value = NSNumber(value: Double(segment.spacing))
            output.addAttribute(segment.carrier.key, value: value, range: segment.range)
        }
        return output
    }
}

extension HwpTextRunBuilder {
    /// 글자 모양의 `script` 슬롯 자간 (배율, 0.2 = 20%).
    func spacingRatio(_ shape: CoreHwp.HwpCharShape, _ script: HwpScript) -> CGFloat {
        CGFloat(value(at: script.slotIndex, in: shape.faceSpacing, default: 0)) / 100
    }

    /// `controlIndex`의 컨트롤이 각주·미주 번호인가 — 본문의 참조(각주·미주 컨트롤)와 내용 앞
    /// 자동 번호(각주·미주 종류). 한글은 이 번호에 자간을 주지 않는다 (#260 실측: 라틴·한글 항목 자간
    /// ±20%에서 참조 `1)`·내용 `10)`의 전진량이 자간 0과 같다) — `appendControlMarker`가 kern 0으로 덮는다.
    static func isNoteNumber(controlIndex: Int?, in paragraph: CoreHwp.HwpParagraph) -> Bool {
        guard let controlIndex, let controls = paragraph.ctrlHeaderArray,
              controls.indices.contains(controlIndex)
        else { return false }
        switch controls[controlIndex] {
        case .footnote, .endnote:
            return true
        case let .autoNumber(other):
            // 표 142를 못 읽은 자동 번호도 각주·미주 번호로 치환된다(`autoNumberReplacements`의 폴백) —
            // 그 번호도 자간을 받지 않는다.
            guard let kind = other.autoNumberInfo?.kind else { return true }
            return kind == .footnote || kind == .endnote
        default:
            return false
        }
    }
}

/// 글자 전진량에 비례하는 자간 (#260, `HwpTextRunBuilder.letterSpacedString`).
enum HwpLetterSpacing {
    /// 자간을 싣는 CoreText 속성 (`HwpTextRunBuilder.letterSpacedString` 문서).
    enum Carrier: Equatable {
        /// `kCTKernAttributeName` — 음수 자간이고 글리프가 커닝에 관여하지 않을 때.
        case kern
        /// `kCTTrackingAttributeName` + kern 0 — 양수 자간이거나 커닝에 관여할 수 있는 글리프.
        case tracking

        var key: NSAttributedString.Key {
            switch self {
            case .kern: kCTKernAttributeName as NSAttributedString.Key
            case .tracking: kCTTrackingAttributeName as NSAttributedString.Key
            }
        }
    }

    /// 같은 자간·같은 운반 속성이 이어지는 범위 하나.
    struct Segment: Equatable {
        var range: NSRange
        /// 자간 (pt) — 묶음 첫 글자의 전진량 × 자간 비율.
        let spacing: CGFloat
        let carrier: Carrier
        /// 글리프가 없어 CoreText가 대체 글꼴로 그리는 묶음의 그 글꼴 — 대체 글꼴이 다른 묶음은 값이
        /// 같아도 한 범위로 묶지 않는다 (경계가 없으면 CoreText는 앞 대체 글꼴을 이어 써서 우리가 잰
        /// 글꼴과 갈릴 수 있다).
        let fallbackFont: CTFont?

        static func == (lhs: Segment, rhs: Segment) -> Bool {
            lhs.range == rhs.range && lhs.spacing == rhs.spacing && lhs.carrier == rhs.carrier
                && sameFont(lhs.fallbackFont, rhs.fallbackFont)
        }

        static func sameFont(_ lhs: CTFont?, _ rhs: CTFont?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): true
            case let (lhs?, rhs?): CFEqual(lhs, rhs)
            default: false
            }
        }

        func continues(_ other: Segment) -> Bool {
            spacing == other.spacing && carrier == other.carrier
                && Self.sameFont(fallbackFont, other.fallbackFont)
        }
    }

    /// chunk 바로 앞 글자 — 짝 커닝은 앞 글자와도 걸리므로 첫 묶음의 운반 속성을 정하는 데 쓴다
    /// (`segments`). 같은 글꼴일 때만 짝이 된다.
    struct Preceding {
        let unit: UniChar
        let font: CTFont
        /// 그 글자가 kern ≠ 0을 지니는가 — 빈칸은 뒤에 빈칸 폭 패스가 kern을 주므로 늘 참이다.
        let carriesKern: Bool

        /// 조판 문자열의 마지막 글자 (없거나 글꼴이 없으면 nil). 속성 사전 전체를 꺼내지 않고 두 키만
        /// 읽는다 — chunk마다 불린다.
        init?(endOf string: NSAttributedString) {
            guard string.length > 0 else { return nil }
            let index = string.length - 1
            guard let fontValue = string.attribute(
                kCTFontAttributeName as NSAttributedString.Key, at: index, effectiveRange: nil
            ), CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
            else { return nil }
            let text = CFAttributedStringGetString(string as CFAttributedString)
            unit = CFStringGetCharacterAtIndex(text, index)
            font = unsafeBitCast(fontValue as CFTypeRef, to: CTFont.self)
            let kern = (string.attribute(
                kCTKernAttributeName as NSAttributedString.Key, at: index, effectiveRange: nil
            ) as? NSNumber)?.doubleValue
            carriesKern = HwpLetterSpacing.receivesSpaceKern(unit) || kern != 0
        }
    }

    /// 빈칸 폭 패스(`applySpaceWidths`)가 kern을 줄 수 있는 글자 — 보통·묶음·고정폭 빈칸.
    static func receivesSpaceKern(_ unit: UniChar) -> Bool {
        unit == 0x20 || unit == 0xA0
    }

    /// 글리프가 없는 묶음을 CoreText가 그리는 대체 글꼴과 그 글리프·전진량.
    struct Fallback {
        let font: CTFont
        let glyph: CGGlyph
        let advance: CGFloat
    }

    /// 묶음마다 자간 (pt) = 그 묶음 첫 글자의 전진량 × `ratio`, 같은 값·같은 운반 속성·같은 대체
    /// 글꼴이 이어지면 한 범위로 합친다.
    ///
    /// 전진량은 `font`의 글리프 전진량이다 — `CTFontGetAdvancesForGlyphs`는 글꼴 행렬(장평)을 이미
    /// 품고 있어 장평 적용 뒤 값이다. 글리프가 없는 글자는 CoreText가 그 글자만 놓고 고르는 대체
    /// 글꼴(`CTFontCreateForString` — 그 묶음이 제 범위를 가지면 CoreText의 선택과 같다)의 전진량을
    /// 쓰고, 대체 글꼴에도 없으면 0이다. 빈칸(U+0020·U+00A0)은 글리프가 있으면 0이다 — 빈칸 폭
    /// 패스가 kern으로 폭과 자간을 함께 준다.
    ///
    /// 운반 속성(`Carrier`)은 다음을 모두 만족할 때만 kern이고 나머지는 tracking이다 — 그때만 kern이
    /// 어떤 커닝도 켜지 않는다(`HwpKerningCoverage`의 "두 글자 모두 kern ≠ 0" 규칙):
    /// - 음수 자간 (양수는 줄 끝 규칙 때문에 tracking — `HwpTextRunBuilder.letterSpacedString`).
    /// - **한 글리프 묶음** — 한 단위 글자이거나 대리 쌍. 결합 부호 묶음은 kern 기능의 문맥 룩업이 부호
    ///   자리를 다시 잡는 글꼴이 있다(실측: Times New Roman `Жx́·`의 부호가 kern에서만 1.52pt 옮겨졌다 —
    ///   표시 위치 조정 룩업이라 커닝 집합에 들지 않는다).
    /// - 그 글리프가 글꼴의 커닝 집합에 들지 않는다 (집합을 모르면 kern을 쓰지 않는다).
    /// - **앞 글자**가 kern ≠ 0을 지닌 같은 글꼴의 커닝 집합 글리프가 아니다 — 빈칸 폭 패스가 kern을
    ///   주는 빈칸이 짝 커닝의 첫 글리프인 글꼴(Times New Roman·Arial의 빈칸)에서 뒤 글자가 kern을
    ///   지니면 빈칸과 그 글자 사이에 짝 커닝이 걸린다. chunk 첫 묶음의 앞 글자는 `preceding`이다.
    static func segments(
        of text: NSString,
        font: CTFont,
        ratio: CGFloat,
        preceding: () -> Preceding? = { nil },
        cache: HwpTextAttributeCache? = nil,
        coverage: (CTFont) -> HwpKerningCoverage.GlyphSet? = HwpKerningCoverage.glyphs(of:)
    ) -> [Segment] {
        let length = text.length
        guard length > 0 else { return [] }
        var units = [UniChar](repeating: 0, count: length)
        text.getCharacters(&units, range: NSRange(location: 0, length: length))
        var glyphs = [CGGlyph](repeating: 0, count: length)
        _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, length)
        var advances = [CGSize](repeating: .zero, count: length)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, length)
        // 커닝 집합은 음수 자간에서만 본다 — 처음 필요할 때 한 번.
        var fontCoverage: HwpKerningCoverage.GlyphSet??
        func chunkCoverage() -> HwpKerningCoverage.GlyphSet? {
            if fontCoverage == nil {
                fontCoverage = .some(coverage(font))
            }
            return fontCoverage ?? nil
        }
        // 앞 글자가 kern ≠ 0을 지닌 이 글꼴의 커닝 집합 글리프인가 — 그 뒤 묶음은 kern을 쓰지 않는다.
        // chunk 앞 글자는 첫 묶음이 kern 후보일 때만 본다 (`precedingBlocksKern`).
        var precededByKerningGlyph: Bool?
        func precedingBlocksKern() -> Bool {
            guard let preceding = preceding(), preceding.carriesKern, CFEqual(preceding.font, font)
            else { return false }
            var unit = preceding.unit
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1)
            return chunkCoverage()?.contains(glyph) ?? true
        }

        var segments: [Segment] = []
        var index = 0
        while index < length {
            let cluster = clusterRange(at: index, units: units, text: text)
            var advance: CGFloat = 0
            var fallback: Fallback?
            if glyphs[index] != 0, !missesTrailingGlyph(cluster, glyphs: glyphs, units: units) {
                let unit = units[index]
                advance = unit == 0x20 || unit == 0xA0 ? 0 : advances[index].width
            } else if let resolved = fallbackGlyph(
                of: cluster, units: units, text: text, font: font, shaped: glyphs[index] != 0,
                cache: cache
            ) {
                fallback = resolved
                advance = resolved.advance
            }
            let spacing = advance * ratio
            var carrier = Carrier.tracking
            if spacing < 0, cluster.length == 1 || isSurrogatePair(cluster, units) {
                if let fallback {
                    // 대체 글꼴 run은 chunk 글꼴의 앞 글자와 짝이 되지 않는다.
                    if let set = coverage(fallback.font), !set.contains(fallback.glyph) {
                        carrier = .kern
                    }
                } else if let set = chunkCoverage(), !set.contains(glyphs[index]),
                          !(precededByKerningGlyph ?? precedingBlocksKern())
                {
                    carrier = .kern
                }
            }
            if ratio < 0 {
                precededByKerningGlyph = fallback == nil && receivesSpaceKern(units[index])
                    && chunkCoverage()?.contains(glyphs[index]) ?? true
            }
            let segment = Segment(
                range: cluster, spacing: spacing, carrier: carrier, fallbackFont: fallback?.font
            )
            if let last = segments.last, last.continues(segment) {
                segments[segments.count - 1].range.length += cluster.length
            } else {
                segments.append(segment)
            }
            index = NSMaxRange(cluster)
        }
        return segments
    }

    /// `index`에서 시작하는 글자 묶음의 범위. 다음 단위가 앞 글자에 붙을 수 없는 흔한 글자이면 대리
    /// 쌍만 보고, 아니면 `rangeOfComposedCharacterSequence`에 묻는다. 첫가끝 초성(U+1100–115F·
    /// U+A960–A97C)은 뒤 **음절**과도 한 묶음이 되므로(L + LV/LVT) 늘 묻는다.
    static func clusterRange(at index: Int, units: [UniChar], text: NSString) -> NSRange {
        let length = units.count
        var end = index + 1
        if UTF16.isLeadSurrogate(units[index]), end < length, UTF16.isTrailSurrogate(units[end]) {
            end += 1
        }
        guard end < length, mayExtendCluster(units[end]) || isChoseong(units[index]) else {
            return NSRange(location: index, length: end - index)
        }
        let composed = text.rangeOfComposedCharacterSequence(at: index)
        return NSRange(location: index, length: max(NSMaxRange(composed), end) - index)
    }

    /// 앞 글자와 한 묶음이 될 수 있는 단위인가 — 결합 부호·이음 문자·변이 선택자·첫가끝 자모·대리 쌍
    /// (이모지 수식·태그) 등. 붙을 수 없다고 확실한 범위만 `false`다: U+0300 미만, CJK 기호·가나·한자
    /// (U+3000–9FFF) 중 결합 부호인 U+302A–302F(한자·한글 방점)·U+3099–309A(가나 탁점)를 뺀 나머지, 한글
    /// 음절. 실제 판정은 Foundation에 맡긴다.
    static func mayExtendCluster(_ unit: UniChar) -> Bool {
        switch unit {
        case 0 ..< 0x0300, 0x3000 ... 0x3029, 0x3030 ... 0x3098, 0x309B ... 0x9FFF,
             0xAC00 ... 0xD7A3:
            false
        default:
            true
        }
    }

    /// 첫가끝 초성 — 뒤의 중성·음절과 한 묶음이 된다.
    private static func isChoseong(_ unit: UniChar) -> Bool {
        (0x1100 ... 0x115F).contains(unit) || (0xA960 ... 0xA97C).contains(unit)
    }

    private static func isSurrogatePair(_ cluster: NSRange, _ units: [UniChar]) -> Bool {
        cluster.length == 2 && UTF16.isLeadSurrogate(units[cluster.location])
    }

    /// 묶음의 첫 글자 **뒤** 단위 중 글꼴에 글리프가 없는 것이 있는가 (대리 쌍의 뒤 반쪽은 글리프 칸이
    /// 비므로 세지 않는다). 그런 묶음은 첫 글자가 글꼴에 있어도 CoreText가 묶음째 대체 글꼴로 그릴 수
    /// 있다 — 실측: Menlo의 `#` + U+FE0F + U+20E3·`☺` + U+FE0F는 Apple Color Emoji 23pt(20pt 기준)로
    /// 그려진다(Menlo `#`은 12.04pt).
    private static func missesTrailingGlyph(
        _ cluster: NSRange, glyphs: [CGGlyph], units: [UniChar]
    ) -> Bool {
        guard cluster.length > 1, !isSurrogatePair(cluster, units) else { return false }
        for offset in cluster.location + 1 ..< NSMaxRange(cluster) where glyphs[offset] == 0 {
            if UTF16.isTrailSurrogate(units[offset]), UTF16.isLeadSurrogate(units[offset - 1]) {
                continue
            }
            return true
        }
        return false
    }

    /// CoreText가 자간(kern·tracking)을 적용하는 조판 문자열 길이의 상한 (UTF-16 단위). 이보다 긴
    /// 문자열은 CoreText가 typesetter·framesetter 모두에서 kern·tracking을 **통째로** 무시한다 (실측
    /// macOS 27: 10,240자 Apple SD 산돌고딕 Neo 한글 음절열의 kern −1이 적용되고 10,241자부터 글자마다·
    /// 일정 kern·tracking 모두 0 — 문자열 안의 줄 나눔과도 무관). 그런 문단은 자간 없이 그려지므로 줄
    /// 끝 자간 보정(`lineEndExcess`)도 하지 않는다 — 하면 적용되지 않은 자간을 빼서 들어가는 줄을
    /// 나눈다 (#260 리뷰).
    static let coreTextSpacingLengthLimit = 10240

    /// 줄(`range`)의 마지막 **내용** 글자의 자간과, 그 글자 뒤에 폭 0 컨트롤 표식이 있는지.
    ///
    /// 마지막 내용 글자는 뒤 공백(`isLineEndWhitespace`)과 폭 0 컨트롤 표식(`isZeroWidthControlMarker`
    /// — 필드 끝·책갈피 등)을 걷어 낸 마지막 글자다. 한글은 줄 끝 자간 규칙에서 그 표식을 없는 것으로
    /// 본다 (#260 리뷰 실측, 한글 12.30.0 build 6523: Menlo 20pt 라틴 자간 ±20% 오른쪽 정렬 `abcd` 뒤에
    /// 하이퍼링크 끝·책갈피를 둬도 `d`가 표식 없는 문단과 같은 498.24pt, 줄 폭 387.5pt의 −20% `aaaaa`
    /// 줄 나눔도 링크 유무와 같은 6단어). 자간은 자간 표식(`HwpAttributedStringKey.letterSpacing`)이 있는
    /// 글자의 tracking, 없으면 kern이다 — 자간 chunk의 공백 아닌 글자에는 자간 말고 kern을 싣는 것이 없다.
    static func lineEnd(
        in attributedString: NSAttributedString, range: NSRange
    ) -> (spacing: CGFloat, followedByControl: Bool) {
        let string = attributedString.string as NSString
        var end = min(NSMaxRange(range), string.length)
        var followedByControl = false
        while end > range.location {
            let unit = string.character(at: end - 1)
            if isLineEndWhitespace(unit) {
                end -= 1
            } else if isZeroWidthControlMarker(unit, in: attributedString, at: end - 1) {
                followedByControl = true
                end -= 1
            } else {
                break
            }
        }
        guard end > range.location,
              attributedString.attribute(
                  HwpAttributedStringKey.letterSpacing, at: end - 1, effectiveRange: nil
              ) != nil
        else { return (0, followedByControl) }
        for carrier in [Carrier.tracking, .kern] {
            if let value = attributedString.attribute(carrier.key, at: end - 1, effectiveRange: nil)
                as? NSNumber
            {
                return (CGFloat(value.doubleValue), followedByControl)
            }
        }
        return (0, followedByControl)
    }

    /// 줄(`range`)의 마지막 내용 글자의 자간 (pt, 없으면 0) — `lineEnd`의 값.
    static func lineEndSpacing(in attributedString: NSAttributedString, range: NSRange) -> CGFloat {
        lineEnd(in: attributedString, range: range).spacing
    }

    /// 줄의 마지막 내용 글자 자간 중 **CoreText가 줄 폭에 넣고 잰** 몫 (pt, 없으면 0).
    ///
    /// 한글은 줄의 마지막 글자에 자간을 주지 않는다 (#260 실측: 오른쪽·가운데·양쪽 정렬과 줄 맞춤이
    /// 모두 마지막 글자를 자간 없는 전진량으로 잰다 — Menlo 20pt `abcd` 라틴 자간 ±20% 오른쪽
    /// 정렬에서 `d`가 오른쪽 끝 − 12.04pt(자간 없는 전진량), 왼쪽 여백으로 줄 폭을 0.5pt씩 바꾼
    /// 표본의 줄 나눔 경계가 자간 생략 모델과 일치). CoreText는 줄 끝 글자의 양수 tracking을 줄 끝
    /// 공백처럼 매달아 이미 빼고 재므로 그 몫은 0이다. 음수(kern·tracking)는 넣고 재고, 양수도 뒤에
    /// 폭 0 컨트롤 표식이 있으면 매달지 못해 넣고 잰다 — 그 둘이 줄바꿈 코어(`HwpLineBreaker`)·한 줄
    /// 허용 정렬(`HwpDrawnTextLayout.slightOverflowAlignmentOffset`)·양쪽 정렬(`HwpWordJustification`)이
    /// 빼는 값이다. 문자열이 `coreTextSpacingLengthLimit`보다 길면 CoreText가 자간을 적용하지 않았으므로 0.
    static func lineEndExcess(in attributedString: NSAttributedString, range: NSRange) -> CGFloat {
        guard attributedString.length <= coreTextSpacingLengthLimit else { return 0 }
        let end = lineEnd(in: attributedString, range: range)
        return end.spacing < 0 || end.followedByControl ? end.spacing : 0
    }

    /// 폭 0 컨트롤 표식 — 개체가 아닌 컨트롤(필드 시작·끝, 책갈피 등)의 U+FFFC
    /// (`HwpTextRunBuilder.appendControlMarker`, 폭 0 run delegate). 글자처럼 취급 개체의 표식은
    /// `inlineObjectHeight`를 지녀 내용 글자다.
    static func isZeroWidthControlMarker(
        _ unit: UniChar, in attributedString: NSAttributedString, at index: Int
    ) -> Bool {
        unit == 0xFFFC
            && attributedString.attribute(
                HwpAttributedStringKey.controlIndex, at: index, effectiveRange: nil
            ) != nil
            && attributedString.attribute(
                HwpAttributedStringKey.inlineObjectHeight, at: index, effectiveRange: nil
            ) == nil
    }

    /// 문자열의 마지막 내용 글자(뒤 공백·폭 0 컨트롤 표식을 뺀 마지막 묶음)에서 자간을 걷는다 — 문단
    /// 번호 라벨의 마지막 글자 (`appendNumberingHeading`). 운반 속성이 어느 쪽이든 kern 0·tracking 없음이
    /// 된다.
    static func removeLastCharacterSpacing(in string: NSMutableAttributedString) {
        let text = string.string as NSString
        var end = text.length
        while end > 0 {
            let unit = text.character(at: end - 1)
            guard isLineEndWhitespace(unit)
                || isZeroWidthControlMarker(unit, in: string, at: end - 1)
            else { break }
            end -= 1
        }
        guard end > 0 else { return }
        let cluster = text.rangeOfComposedCharacterSequence(at: end - 1)
        guard string.attribute(
            HwpAttributedStringKey.letterSpacing, at: cluster.location, effectiveRange: nil
        ) != nil else { return }
        string.removeAttribute(kCTTrackingAttributeName as NSAttributedString.Key, range: cluster)
        let kern = kCTKernAttributeName as NSAttributedString.Key
        string.addAttribute(kern, value: NSNumber(value: 0), range: cluster)
    }

    /// CoreText가 줄 끝에서 매달리는 공백으로 다루는 글자(`CTLineGetTrailingWhitespaceWidth`가 세는 것)
    /// — 탭·줄 나눔·문단 구분과 유니코드 공백 문자(Zs: 빈칸·묶음·고정폭 빈칸 U+00A0·전각 빈칸 U+3000 등).
    /// 묶음·고정폭 빈칸을 내용 글자로 보면 빈칸 폭 패스가 준 kern을 자간으로 읽는다(리뷰 실측).
    static func isLineEndWhitespace(_ unit: UniChar) -> Bool {
        switch unit {
        case 0x09, 0x0A, 0x0D, 0x2028, 0x2029:
            true
        default:
            Unicode.Scalar(unit)?.properties.generalCategory == .spaceSeparator
        }
    }

    /// 글리프가 없는 묶음 — CoreText가 고를 대체 글꼴과 그 글리프·전진량. 대체 글꼴에도 없으면 nil.
    /// (글꼴, 묶음 단위열)의 순수 함수라 문서 캐시(`HwpTextAttributeCache.fallback`)를 거친다 — 결정론
    /// resolver(Menlo)에서는 한글 음절이 전부 이 길이라 헌법주석 한 번 로드에 4초가 들었다.
    ///
    /// `shaped`는 첫 글자는 글꼴에 있고 뒤 단위가 없는 묶음(`missesTrailingGlyph`)이다 — 그 묶음은
    /// `CTFontCreateForString`이 CoreText의 run 글꼴과 갈린다(실측: Menlo `❤` + U+FE0E는 Menlo로 그려지는데
    /// 대체 글꼴 조회는 Zapf Dingbats를 낸다). 그래서 묶음만 조판해 첫 run의 글꼴·첫 글리프·폭을 쓴다 —
    /// 드물고(이모지 변이 선택자·키캡) 결과가 캐시되므로 조판 비용은 묶음 종류마다 한 번이다.
    private static func fallbackGlyph(
        of cluster: NSRange, units: [UniChar], text: NSString, font: CTFont, shaped: Bool,
        cache: HwpTextAttributeCache?
    ) -> Fallback? {
        let resolve = { () -> Fallback? in
            if shaped {
                return shapedFallback(of: text.substring(with: cluster), font: font)
            }
            let fallback = CTFontCreateForString(
                font, text as CFString, CFRange(location: cluster.location, length: cluster.length)
            )
            let leadsPair = UTF16.isLeadSurrogate(units[cluster.location]) && cluster.length >= 2
            let width = leadsPair ? 2 : 1
            var characters = Array(units[cluster.location ..< cluster.location + width])
            var glyphs = [CGGlyph](repeating: 0, count: width)
            guard CTFontGetGlyphsForCharacters(fallback, &characters, &glyphs, width),
                  glyphs[0] != 0
            else { return nil }
            var size = CGSize.zero
            CTFontGetAdvancesForGlyphs(fallback, .horizontal, &glyphs, &size, 1)
            let unit = units[cluster.location]
            return Fallback(
                font: fallback, glyph: glyphs[0],
                advance: unit == 0x20 || unit == 0xA0 ? 0 : size.width
            )
        }
        guard let cache else { return resolve() }
        let clusterUnits = Array(units[cluster.location ..< NSMaxRange(cluster)])
        return cache.fallback(for: clusterUnits, in: font, create: resolve)
    }

    /// `cluster`를 `font`로 조판한 첫 run의 글꼴·첫 글리프·폭 (`fallbackGlyph`의 `shaped`).
    private static func shapedFallback(of cluster: String, font: CTFont) -> Fallback? {
        let string = NSAttributedString(
            string: cluster, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let line = CTLineCreateWithAttributedString(string)
        let runs = CTLineGetGlyphRuns(line) as NSArray
        guard runs.count > 0, CFGetTypeID(runs[0] as CFTypeRef) == CTRunGetTypeID() else {
            return nil
        }
        let run = unsafeBitCast(runs[0] as CFTypeRef, to: CTRun.self)
        guard CTRunGetGlyphCount(run) > 0,
              let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
              CFGetTypeID(runFont as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        var glyph = CGGlyph()
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        let width = CTRunGetTypographicBounds(run, CFRange(), nil, nil, nil)
        return Fallback(
            font: unsafeBitCast(runFont as CFTypeRef, to: CTFont.self), glyph: glyph,
            advance: CGFloat(width)
        )
    }
}
