import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 변경 추적 (PARA_RANGE_TAG kind 16/17)과 메모 (댓글) 앵커 범위 마킹.
extension HwpTextRunBuilder {
    /// PARA_RANGE_TAG의 변경 추적 마크 (16 삽입 / 17 삭제)를 한글.app처럼
    /// 표시한다: 삽입 = 빨강 글자 + 빨강 밑줄, 삭제 = 빨강 글자 + 빨강 취소선.
    func applyTrackChangeMark(
        _ mark: UInt32,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard mark == 16 || mark == 17 else { return }
        let red = CGColor.hwpTrackChange
        attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = red
        if mark == 17 {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = red
        } else {
            // CT 밑줄은 폰트 밑줄 위치 (얕음) — 한글 실물은 베이스라인에서
            // 반 x-height가량 아래 (track-changes 실측). 렌더러가 직접 그린다.
            attributes[HwpAttributedStringKey.trackInsertUnderline] = red
        }
    }

    /// 변경 추적 range tag (kind 16 삽입 / 17 삭제)를 시작 위치 오름차순으로
    /// 정렬해 돌려준다. 문자 루프에서 단조 커서로 sweep하기 위한 것으로,
    /// 문자마다 전체 배열을 다시 스캔하는 O(문자×태그)를 없앤다 (#11).
    static func trackChangeIntervals(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [(start: UInt32, end: UInt32, kind: UInt32)] {
        (paragraph.paraRangeTagArray ?? []).compactMap { tag in
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { return nil }
            return (start: tag.start, end: tag.end, kind: kind)
        }
        .sorted { $0.start < $1.start }
    }

    /// position (원본 WCHAR 스트림 위치)이 속한 변경 추적 range tag의 kind.
    /// 16 (삽입)/17 (삭제) 외의 태그는 무시한다.
    static func trackChangeMark(
        at position: UInt32,
        in paragraph: CoreHwp.HwpParagraph
    ) -> UInt32 {
        for tag in paragraph.paraRangeTagArray ?? [] {
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { continue }
            if position >= tag.start, position < tag.end {
                return kind
            }
        }
        return 0
    }

    /// 메모 (댓글) 필드가 감싸는 앵커 텍스트의 WCHAR 스트림 범위.
    /// extended 컨트롤 문자 (필드 시작, ctrl 순서 = ctrlHeaderArray 순서)부터
    /// 다음 필드 끝 inline 문자 (코드 4)까지.
    static func memoAnchorRanges(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [Range<UInt32>] {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.contains(where: {
                  if case .memo = $0 {
                      true
                  } else {
                      false
                  }
              })
        else { return [] }
        // 필드는 코드 3 시작 ~ 코드 4 끝으로 LIFO 중첩된다 — 필드 depth와
        // depth별 memo 스택으로 매칭 종결자에서만 닫아, memo 안 중첩 필드
        // (하이퍼링크 등)의 끝 마커가 바깥 앵커를 조기 종료하거나 중첩 memo가
        // 바깥 start를 덮지 않게 한다 (HwpTextRunBuilder 하이퍼링크 스택과 동일, #2).
        var ranges: [Range<UInt32>] = []
        var position: UInt32 = 0
        var ordinal = 0
        var fieldDepth = 0
        var memoStack: [(depth: Int, start: UInt32)] = []
        for hwpChar in paragraph.paraText?.charArray ?? [] {
            let length: UInt32 = hwpChar.type == .char ? 1 : 8
            if hwpChar.type == .extended {
                if hwpChar.value == 3 {
                    fieldDepth += 1
                    if ordinal < ctrls.count, case .memo = ctrls[ordinal] {
                        memoStack.append((depth: fieldDepth, start: position + length))
                    }
                }
                ordinal += 1
            } else if hwpChar.type == .inline, hwpChar.value == 4 {
                if let top = memoStack.last, top.depth == fieldDepth {
                    if position > top.start {
                        ranges.append(top.start ..< position)
                    }
                    memoStack.removeLast()
                }
                if fieldDepth > 0 {
                    fieldDepth -= 1
                }
            }
            position += length
        }
        // 빌더의 단조 sweep은 lowerBound 오름차순을 전제한다 — 중첩 close 순서
        // (안쪽 먼저)로 어긋난 정렬을 복원한다.
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}

extension HwpTextRunBuilder {
    /// 한글의 기본 공백 폭 규칙: '글꼴에 어울리는 빈칸'(doesAdjustBlank)이
    /// 꺼져 있으면 공백 advance를 폰트 고유 폭 대신 글자 크기의 1/2로 맞춘다.
    /// 실측 (2026-07-10 plain-text-minimal 실물 픽셀): 한글.app 공백 advance
    /// ≈ 0.5em, HCR Batang 고유 공백 ≈ 0.3em — 부족분을 kern으로 더한다.
    static func applyFixedSpaceWidth(
        to attributed: NSMutableAttributedString,
        includesOrdinarySpace: Bool
    ) {
        let text = attributed.string as NSString
        var index = 0
        while index < text.length {
            // U+00A0은 묶음·고정폭 빈칸(30/31)이 오는 자리다 — 보통 빈칸과
            // 달리 문서 설정 게이트 **밖에서** 늘 0.5em으로 맞춘다:
            // "고정폭" 빈칸의 폭이 글꼴에 따라 달라지면 이름과 모순이다.
            // 묶음 빈칸(30)도 같은 문자로 접히므로 함께 따라간다 — 둘을
            // 가르려면 별도 표식이 필요하고 그 판단은 실물 대조 항목이다.
            let unit = text.character(at: index)
            if unit == 0xA0 || (unit == 0x20 && includesOrdinarySpace) {
                let attrs = attributed.attributes(at: index, effectiveRange: nil)
                if let fontValue = attrs[kCTFontAttributeName as NSAttributedString.Key],
                   CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
                {
                    // swiftlint:disable:next force_cast
                    let font = fontValue as! CTFont
                    // 공백 폭 목표는 첨자 축소 전·상대크기 적용 후 크기의
                    // 0.5em (라운드 11·12 실측: 첨자 행 공백 = 본문 공백,
                    // 상대크기 170 줄 공백 = 1.7배)
                    let base = (attrs[HwpAttributedStringKey.spaceTargetSize]
                        as? NSNumber).map { CGFloat($0.doubleValue) }
                    let kern = Self.fixedSpaceKern(for: font, targetEm: base, character: unit)
                    if abs(kern) > 0.01 {
                        attributed.addAttribute(
                            kCTKernAttributeName as NSAttributedString.Key,
                            value: NSNumber(value: Double(kern)),
                            range: NSRange(location: index, length: 1)
                        )
                    }
                }
            }
            index += 1
        }
    }

    /// 공백 글리프의 고유 advance와 0.5em 목표의 차 (폰트별 캐시 없이 즉석 계산 —
    /// CTFontGetAdvancesForGlyphs는 가볍고 chunk 단위로만 불린다)
    static func fixedSpaceKern(
        for font: CTFont,
        targetEm: CGFloat? = nil,
        character: UniChar = 0x20
    ) -> CGFloat {
        // 보정 대상 문자 자신의 advance를 잰다 — U+0020으로 고정하면 고유
        // advance가 다른 공백(U+00A0)에서 목표 폭이 어긋난다.
        var character = character
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let target = (targetEm ?? CTFontGetSize(font)) * 0.5
        return target - advance.width
    }
}

extension HwpTextRunBuilder {
    /// 위 첨자 글꼴 크기 배율 — 실물 실측 (CharShapeProperty): 본문의 ~67%
    static let superscriptScale: CGFloat = 0.67
    /// 위 첨자 베이스라인 상승 배율 (기준 글자 크기 대비)
    static let superscriptBaselineRatio: CGFloat = 0.33
    /// 아래 첨자 베이스라인 하강 배율 (실물: 다음 줄 방향 ~0.35줄)
    static let subscriptBaselineRatio: CGFloat = 0.30
}

/// 조판 문자열 생성 보조 (메모 앵커 sweep·문자별 방출 텍스트).
extension HwpTextRunBuilder {
    /// 메모 앵커 구간 커서를 `position`까지 앞으로만 밀고 포함 여부를 준다
    /// (`build`의 sweep 규약 — position은 단조 증가한다).
    func memoAnchor(
        at position: UInt32,
        in ranges: [Range<UInt32>],
        cursor: inout Int
    ) -> Bool {
        while cursor < ranges.count, ranges[cursor].upperBound <= position {
            cursor += 1
        }
        return cursor < ranges.count && ranges[cursor].contains(position)
    }

    /// 이 문자가 조판 문자열에 낼 텍스트.
    ///
    /// 문단 끝(13)은 `controlText`가 접지만, **한 줄 끝(10) 바로 뒤**에서는 빈 줄
    /// 앵커로 빈칸(U+0020)을 낸다. CoreText는 하드 개행 뒤에 내용이 있어야 그 줄을
    /// 만들기 때문이다 — `"가\n"`은 한 줄이고 `"가\n<무언가>"`가 두 줄이다. 앵커
    /// 없이 접으면 한글이 라인 캐시에 배정해 둔 마지막 빈 줄이 사라져, 캐시를
    /// 쓰지 않는 측정 경로(글상자·캐시 무효 문단·안전밸브로 linesegarray를 폐기한
    /// HWPX 문단)에서 문단 높이가 한 줄만큼 짧아진다 (실측:
    /// `legacy-common-control-property` Section9의 407 WCHAR 문단, 폭 400에서
    /// 접기 전 9줄 144pt → 앵커 없이 접으면 8줄 128pt → 앵커를 넣으면 다시
    /// 9줄 144pt).
    ///
    /// **앵커를 U+000D로도 U+200B로도 두지 않는다.** U+000D를 남기면 #137이 고친
    /// 조판 부호가 그 빈 줄에 그대로 다시 그려진다. U+200B는 잉크가 없지만
    /// `isWhitespace`가 **거짓**이라 조판 문자열을 소비하는 계약을 조용히 깬다:
    /// `HwpAccessibilityContent.accessibilityLabel`의 "공백만 남으면 버린다"
    /// 판정을 통과해 읽을 것이 없는 VoiceOver 정지점을 만들고, 복사 문자열에는
    /// 어떤 다듬기에도 걸리지 않는 보이지 않는 문자가 남는다 (평문·RTF는 U+FFFC만
    /// 지운다 — `HwpSelectionGeometry.strippingControlMarkers`). 빈칸은 U+000D와
    /// 같은 공백 부류라 접기 전 계약이 그대로 유지된다. 잉크는 어느 폰트에서도
    /// 없고 (실측: HY울릉도M·함초롬바탕·Apple SD Gothic Neo 모두 마지막 줄 잉크
    /// 폭 0) 빈 줄이라 진행 폭도 화면에 드러나지 않는다.
    func emittedText(
        of hwpChar: CoreHwp.HwpChar,
        pendingHighSurrogate: inout UInt16?,
        followsLineBreak: inout Bool
    ) -> String {
        var text = string(from: hwpChar, pendingHighSurrogate: &pendingHighSurrogate)
        if text.isEmpty, hwpChar.type == .char, hwpChar.value == 13, followsLineBreak {
            text = " "
        }
        if !text.isEmpty {
            followsLineBreak = text.unicodeScalars.last == "\u{000A}"
        }
        return text
    }
}

/// 그대로 디코드하면 안 되는 제어 문자 변환.
extension HwpTextRunBuilder {
    /// WCHAR를 그대로 디코드하면 안 되는 제어 문자의 표시 대체 텍스트.
    ///
    /// 묶음 빈칸(30)·고정폭 빈칸(31)은 U+001E/U+001F로 디코드되어 CoreText가
    /// 폭 0으로 그린다 — 빈칸이 사라지고 줄바꿈이 달라진다. 두 포맷 공통
    /// 경로다 (바이너리 `HwpParaText`의 default 분기와 HWPX의 nbSpace·fwSpace가
    /// 같은 값을 낸다).
    ///
    /// 고정폭 빈칸의 "양쪽 정렬에서 늘어나지 않음"은 조판이 모델링하지
    /// 않으므로 폭이 같은 U+00A0을 쓴다 — U+2007처럼 폭이 다른 문자를 쓰면
    /// 실물보다 넓어진다.
    ///
    /// 하이픈(24, HWPX `<hp:hyphen/>`)은 아무것도 그리지 않는다 — 실측
    /// (한글.app 12.30, 하이픈 유무 대조 문서): 줄 중간 글리프 없음·줄바꿈
    /// 기회 없음·줄 끝 하이픈 없음·글자 수 미집계. U+00AD로 옮기면 실물에
    /// 없는 줄바꿈 기회가 생기고, 그대로 두면 표시·복사 문자열에 U+0018이
    /// 남는다.
    ///
    /// 문단 끝(13)도 마찬가지로 떨군다 (#137). 모든 문단의 WCHAR 스트림이
    /// 13으로 끝나므로 (바이너리 `HwpParaText`의 `case 0, 1, 13`, HWPX
    /// `HwpxParagraphMapper`의 문단 끝 합성) 그대로 두면 폐해가 셋이다.
    ///
    /// 1. U+000D에 잉크가 있는 폰트에서 문단 끝마다 조판 부호가 그려진다 —
    ///    실측 2026-09-04: 한컴오피스 12.30 번들 187개 페이스 중 25개(전부 HY
    ///    계열)가 U+000D를 `¬` 모양으로 그리고, noori 3쪽 비교표 셀의 라틴
    ///    슬롯인 HY울릉도M이 그중 하나다.
    /// 2. 줄 높이가 부푼다. U+000D는 `HwpScript.detect`의 default로 `.english`가
    ///    되어 **라틴 슬롯 폰트**로 조판되는데, 그 폰트가 본문 글꼴과 다르면
    ///    CTLine ascent를 자기 기준으로 끌어올린다 (실측 13pt: "보도일시"를
    ///    휴먼명조로 조판하면 ascent 11.172인데 U+000D를 함초롬바탕으로 붙이면
    ///    13.910). 표 셀은 세로 가운데 정렬이라 글이 위로 밀렸다.
    /// 3. 표시·복사·낭독 문자열에 U+000D가 실린다 (`HwpSelectionGeometry`의
    ///    평문·RTF와 `HwpAccessibilityContent`의 라벨은 U+FFFC만 지운다).
    ///
    /// 조판 폭에는 기여하지 않으므로 (CoreText가 문단 종결자 run의 진행 폭을
    /// 0으로 만든다 — 실측: `"구 분"`과 `"구 분\r"`의
    /// `CTLineGetTypographicBounds`가 같다) 떨궈도 줄 폭·줄바꿈은 그대로다.
    /// 예외는 한 줄 끝(10) 바로 뒤에 오는 문단 끝뿐이라 `build`가 그 자리에만
    /// 빈 줄 앵커(빈칸)를 넣는다 — `emittedText` 참조.
    ///
    /// **한 줄 끝(10)은 남긴다** — 의도된 줄 나눔이라 U+000A로 조판되어야 한다.
    static func controlText(_ unit: UInt16) -> String? {
        switch unit {
        case 13, 24:
            ""
        case 30, 31:
            "\u{00A0}"
        default:
            nil
        }
    }
}
