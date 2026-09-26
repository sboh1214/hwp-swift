import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 한글 줄 **전진량** 규칙 — 표 46(표 44) 줄 간격 종류와 값 (#180·#192·#198).
///
/// 한글의 줄 상자는 줄마다 **그 줄의 상대크기 적용 전 기본 글자 크기 최댓값**이고
/// (키 큰 글자처럼 취급 개체가 있으면 개체 높이), 전진량은 그 상자에 줄 간격 종류를
/// 적용한 값이다. 글꼴 지표(ascent·descent·leading)는 관여하지 않는다 — 한글 12.30.0
/// 이 저장한 줄 캐시(`PARA_LINE_SEG`)의 `vertsize`·`spacing`이 그대로 이 규칙이다
/// (2026-09-12 스윕: 글자 크기 8종 × 종류 4종 × 글꼴 3종 × 상대크기 2종 전부).
/// MS 워드 호환 문서(#194)는 글자 상자가 글꼴 줄 상자(`HwpMsWordLineBox`)로 바뀔 뿐
/// 종류별 규칙은 같다 (2026-09-20 실측 `cm194-spacing`: Apple SD 산돌고딕 Neo 10pt 상자
/// 1559 HWPUNIT에 고정 5·16·30 → 500·1600·3000, 여백만 0·3·10 → 1559·1859·2559, 최소
/// 5·16·30 → 1559·1600·3000, 비율 100·160·200·300·80 → 1559·2491·3115·4671·1247).
///
/// | 종류 | 값 | 전진량 |
/// | --- | --- | --- |
/// | 비율(`percent`) | p % | 상자 + 글자 상자 × (p − 100) / 100 |
/// | 고정(`fixed`) | v pt | v (상자보다 작으면 줄이 겹친다 — 한글도 그렇다) |
/// | 여백만 지정(`marginOnly`) | v pt | 상자 + v |
/// | 최소(`atLeast`) | v pt | max(상자, v) |
///
/// **비율의 여분은 글자 상자 기준이다** — 개체가 상자를 정한 줄에서도 `spacing`은 그 줄
/// 글자들의 기본 크기 × (p − 100)/100이다 (실물 캐시: `CCL` 40.87pt 로고 줄의 `spacing`
/// 600 = 10pt × 0.6, `noori` 61.34pt 그림 줄 840 = 12pt × 0.7, 627.01pt 표 줄 1052 =
/// 15pt × 0.7, `BinData` 199.38pt 그림 줄 600). 여백만·최소·고정은 개체 줄에서 상자
/// (= max(글자, 개체))에 그대로 적용한다 (2026-09-15 합성 실측).
public struct HwpLineSpacingRule: Equatable, Sendable {
    /// 표 46 줄 간격 종류 — raw 값이 표의 종류 번호다.
    public enum Kind: Int, Sendable {
        /// 글자에 따라(%)
        case percent = 0
        /// 고정값
        case fixed = 1
        /// 여백만 지정
        case marginOnly = 2
        /// 최소
        case atLeast = 3
    }

    public let kind: Kind
    /// `percent`면 % (예: 160), 나머지는 pt.
    public let value: CGFloat

    public init(kind: Kind, value: CGFloat) {
        self.kind = kind
        self.value = value
    }

    /// 문단 모양의 줄 간격 — 고정·최소·여백만 값은 표 43 여백 계열과 같은 **1/2 단위**
    /// (HWPUNIT × 2)로 저장된다 (#192 실측: 한글 대화상자 고정 16pt → 저장값 3200,
    /// HWPX `hp:switch`의 `HwpUnitChar` 갈래 1600 · `default` 갈래 3200 — 매퍼가 HWP
    /// 이진 규약으로 올려 싣는다). 비율은 % 그대로다.
    public init(paraShape: CoreHwp.HwpParaShape) {
        let kind = Kind(rawValue: Int(paraShape.resolvedLineSpacingKind.rawValue)) ?? .percent
        let raw = paraShape.resolvedLineSpacingValue
        switch kind {
        case .percent:
            self.init(kind: .percent, value: CGFloat(raw))
        case .fixed, .marginOnly, .atLeast:
            self.init(kind: kind, value: HwpUnits.points(fromHwpUnit: raw) / 2)
        }
    }

    /// 줄 하나의 전진량 (줄 상자 상단에서 다음 줄 상자 상단까지).
    ///
    /// - `textBoxHeight`: 그 줄 글자 run들의 기본 글자 크기 최댓값.
    /// - `objectHeight`: 그 줄이 예약한 글자처럼 취급 개체 높이 최댓값 (없으면 0).
    ///
    /// 줄 상자는 둘 가운데 큰 것이다 — 한글 문서의 규칙. 줄 상자가 그 최댓값이 아닌 줄은
    /// `advance(lineBoxHeight:textBoxHeight:)`에 상자를 직접 준다: MS 워드 호환 문서, 그리고
    /// 글자처럼 취급 개체 마커의 글자 모양이 글자보다 큰 한글 문서 줄 — 그 크기는 비율 여분의
    /// 기준에는 들어도 줄 상자에는 들지 않는다 (#217).
    public func advance(textBoxHeight: CGFloat, objectHeight: CGFloat) -> CGFloat {
        advance(
            lineBoxHeight: max(max(0, textBoxHeight), max(0, objectHeight)),
            textBoxHeight: textBoxHeight
        )
    }

    /// 줄 하나의 전진량 — `lineBoxHeight`는 줄 상자 높이(한글 줄 캐시의 `vertsize`,
    /// `HwpDrawnTextLayout.LineMetrics.boxHeight`), `textBoxHeight`는 비율 여분의 기준이
    /// 되는 글자 상자 높이(`LineMetrics.textBoxHeight`)다. 둘은 독립이다 — MS 워드 호환
    /// 문서에서 20pt 글자 모양의 표 마커가 든 10pt 줄은 상자 15.59pt에 여분 기준 20pt다
    /// (한글 캐시 `vertsize` 1559·160% `spacing` 1200, 2026-09-20 `cm194-markers`).
    ///
    /// **비율의 여분은 4 HWPUNIT(0.04pt) 양자다** — 글자 상자를 4 HWPUNIT 단위로 내림한
    /// 뒤 (p − 100)%를 곱해 반올림한다. 한글 12.30 실측 (2026-09-20, MS 워드 호환 합성
    /// 문서의 줄 캐시): Apple SD 산돌고딕 Neo 10pt 상자 1559에 160·200·300·80%의
    /// `spacing`이 932·1556·3112·−312 (1559 ÷ 4 = 389 → 389 × 0.6 = 233.4 → 233 × 4;
    /// 1559 × 0.6 = 935가 아니다), Menlo 10pt 1515 → 908·1512·3024 (378 × 0.6 = 226.8 →
    /// 227 × 4), 함초롬돋움 10pt 1692 → 1016, 20pt 3383 → 2028, Apple SD 30pt 4678 → 2804.
    /// 한글 문서의 실물 캐시도 같다 — `CCL`·`noori` 15pt 170% 줄의 `spacing` 1052 (1500 ÷ 4
    /// = 375 → 262.5 → 263 × 4; 15 × 0.7 = 10.50이 아니다), `legacy-common-control-property`
    /// 각주 9pt 130% 6,920줄 전부 272 (225 × 0.3 = 67.5 → 68; 270이 아니다), 10.5pt 160%
    /// 628 (1050 ÷ 4 = 262.5 → **262** × 0.6 = 157.2 → 157 — 내림이 상자에도 걸린다), 11pt
    /// 130% 332, 9.5pt 130% 284, `noori` 13pt 130% 392·15.5pt 160% 928. 반올림은 .5를
    /// 올린다 (67.5·82.5·97.5·262.5 전부). 상자가 4의 배수인 보통의 글자 크기(10·12·20pt…)
    /// 에서는 산술 그대로다.
    public func advance(lineBoxHeight: CGFloat, textBoxHeight: CGFloat) -> CGFloat {
        let text = max(0, textBoxHeight)
        let box = max(0, lineBoxHeight)
        let advance: CGFloat = switch kind {
        case .percent:
            box + Self.percentShare(of: text, percent: value)
        case .fixed:
            value
        case .marginOnly:
            box + value
        case .atLeast:
            max(box, value)
        }
        // 0·음수 전진량은 줄이 같은 자리에 겹쳐 뒤 줄이 앞 줄 위로 올라간다 — 고정 0이나
        // 비율 0은 저작 UI가 막지만 손상 문서가 실을 수 있으므로 1pt를 바닥으로 둔다.
        return max(1, advance)
    }

    /// 비율 줄 간격의 여분 (pt) — 글자 상자 `textBoxHeight`(pt)를 HWPUNIT로 옮겨 4 단위로
    /// 내림한 몫에 (p − 100)%를 곱해 반올림하고 다시 pt로 (위 `advance` 실측). 곱을 먼저 하고
    /// 100으로 나눠야 375 × 70 / 100 = 262.5가 정확히 떨어진다 (0.7 × 375는 262.4999…).
    static func percentShare(of textBoxHeight: CGFloat, percent: CGFloat) -> CGFloat {
        let quanta = Int((max(0, textBoxHeight) * 100).rounded()) / 4
        let share = (CGFloat(quanta) * (percent - 100) / 100).rounded()
        return share * 4 / 100
    }

    // MARK: 조판 문자열 속성

    /// `HwpAttributedStringKey.lineSpacing` 값 — 종류 raw 값과 값을 담은 NSArray.
    public var attributeValue: NSArray {
        [NSNumber(value: kind.rawValue), NSNumber(value: Double(value))]
    }

    /// `attributeValue`의 역 — 형식이 다르면 nil.
    public init?(attributeValue: Any?) {
        guard let array = attributeValue as? NSArray, array.count == 2,
              let kindNumber = array[0] as? NSNumber, let valueNumber = array[1] as? NSNumber,
              let kind = Kind(rawValue: kindNumber.intValue)
        else { return nil }
        self.init(kind: kind, value: CGFloat(valueNumber.doubleValue))
    }

    /// 문자열 `location`의 줄 간격 규칙 — 조판 문자열이 실은 규칙
    /// (`HwpAttributedStringKey.lineSpacing`, `HwpTextRunBuilder.attachParagraphStyle`)이
    /// 있으면 그것이고, 없으면 (공개 `HwpPaintCommand.drawText` 호출자가 CT 문단 스타일만
    /// 단 문자열) 그 스타일의 줄 높이 지정을 같은 상자 모델로 읽는다:
    /// `lineHeightMultiple` → 비율, `minimumLineHeight` == `maximumLineHeight` > 0 → 고정,
    /// `minimumLineHeight` > 0 → 최소, `lineSpacingAdjustment` > 0 → 여백만, 아니면 비율 100%.
    static func rule(
        in attributedString: NSAttributedString, at location: Int
    ) -> HwpLineSpacingRule {
        guard attributedString.length > 0 else { return .naturalPercent }
        let index = min(max(location, 0), attributedString.length - 1)
        if let rule = HwpLineSpacingRule(attributeValue: attributedString.attribute(
            HwpAttributedStringKey.lineSpacing, at: index, effectiveRange: nil
        )) {
            return rule
        }
        return fallback(from: HwpLineBreaker.paragraphStyle(in: attributedString, at: index))
    }

    /// CT 문단 스타일만 있는 문자열의 규칙 (위 `rule(in:at:)` 참조).
    static func fallback(from style: CTParagraphStyle?) -> HwpLineSpacingRule {
        let multiple = HwpLineBreaker.paragraphCGFloat(.lineHeightMultiple, in: style) ?? 0
        if multiple > 0 {
            return HwpLineSpacingRule(kind: .percent, value: multiple * 100)
        }
        let minimum = max(0, HwpLineBreaker.paragraphCGFloat(.minimumLineHeight, in: style) ?? 0)
        let maximum = max(0, HwpLineBreaker.paragraphCGFloat(.maximumLineHeight, in: style) ?? 0)
        if minimum > 0, abs(minimum - maximum) < 0.001 {
            return HwpLineSpacingRule(kind: .fixed, value: minimum)
        }
        if minimum > 0 {
            return HwpLineSpacingRule(kind: .atLeast, value: minimum)
        }
        let spacing = HwpLineBreaker.paragraphCGFloat(.lineSpacingAdjustment, in: style) ?? 0
        if spacing > 0 {
            return HwpLineSpacingRule(kind: .marginOnly, value: spacing)
        }
        return .naturalPercent
    }

    /// 비율 100% — 규칙도 CT 줄 높이 지정도 없는 문자열의 기본값 (줄 상자 = 글자 크기).
    static let naturalPercent = HwpLineSpacingRule(kind: .percent, value: 100)
}

public extension HwpAttributedStringKey {
    /// 문단의 줄 간격 규칙 (`HwpLineSpacingRule.attributeValue`, #180) — 조판 문자열 전체에
    /// 붙는다 (`HwpTextRunBuilder.attachParagraphStyle`). 측정(`HwpParagraphLayout.layout`)과
    /// 렌더(`HwpDrawnTextLayout.lines`)가 **줄바꿈 뒤** 줄마다 이 규칙으로 전진량을 낸다 —
    /// CT 문단 스타일의 줄 높이 지정은 줄바꿈과 서식 복사(`HwpSelectionRTF`)에만 쓰인다.
    static let lineSpacing = NSAttributedString.Key("hwp.lineSpacing")
}

/// 측정과 렌더가 **공유하는** 줄 전진량 — 줄바꿈 결과(`HwpLineBreaker.FrameChunk`)의
/// 줄마다 상자 높이(`HwpDrawnTextLayout.lineMetrics`)에 줄 간격 규칙을 적용하고, 그 줄이
/// 문단을 끝내면 문단 사이 간격을 더한다.
///
/// `HwpParagraphLayout.makeLineFrames`(측정)와 `HwpDrawnTextLayout.lineGeometries`(렌더)가
/// 둘 다 `advanceParts(of:in:)`로 같은 값을 쌓는다 — 측정은 그 합(`advances(of:in:)`)을, 렌더는
/// 두 몫을 받아 더하고 줄 몫은 링크 클릭 띠(#233)에도 쓴다. 한쪽만 바꾸면 문단 높이(쪽 나눔)와
/// 그려지는 줄이 갈린다 (`Sources/HwpKitCore/AGENTS.md` "측정·렌더 공유 줄바꿈 코어").
/// CT 줄 origin·슬롯은 세로 배치에 쓰지 않는다 (#178·#180: CT는 글꼴 지표로 슬롯을 잡고
/// 못박은 높이에 안 들어가는 글자가 있으면 슬롯을 늘리거나 줄을 놓지 않는다 — #198·#202).
enum HwpLineAdvance {
    /// 청크의 커밋된 줄들(`0 ..< keepCount`)의 전진량 — 줄 상자 전진량 + 그 줄 뒤 문단 사이
    /// 간격. 마지막 커밋 줄 뒤의 간격은 다음 청크 첫 줄(`chunk.nextStart`)과의 것이고,
    /// 문자열 끝이면 0이다 (문단 자신의 아래 간격은 `HwpParagraphLayout.layout`이 더한다).
    static func advances(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString
    ) -> [CGFloat] {
        advanceParts(of: chunk, in: attributedString).map { $0.line + $0.gap }
    }

    /// `advances(of:in:)`의 두 몫 — 줄 자신의 전진량(`line`, 줄 상자 × 줄 간격 규칙)과 그 뒤 문단
    /// 사이 간격(`gap`). 렌더(`HwpDrawnTextLayout.lineGeometries`)는 합으로 줄을 타일하고, 줄의 링크
    /// 클릭 띠(#233, `HwpDrawnTextLayout.ClickBand`)는 `line`만 쓴다 — 문단 사이 간격은 어느 줄의
    /// 띠도 아니다.
    static func advanceParts(
        of chunk: HwpLineBreaker.FrameChunk,
        in attributedString: NSAttributedString
    ) -> [(line: CGFloat, gap: CGFloat)] {
        let text = attributedString.string as NSString
        return (0 ..< chunk.keepCount).map { index in
            let line = chunk.lines[index]
            let range = CTLineGetStringRange(line)
            let next = index + 1 < chunk.lines.count
                ? CTLineGetStringRange(chunk.lines[index + 1]).location
                : chunk.nextStart
            let gap = next < attributedString.length
                ? paragraphGap(
                    afterLine: range, nextLocation: next, in: attributedString, text: text
                )
                : 0
            return (lineAdvance(of: line, at: range.location, in: attributedString), gap)
        }
    }

    /// 줄 하나의 상자 전진량 (문단 사이 간격 제외) — slight-overflow 한 줄과 청크 줄이 같은
    /// 산식을 쓴다.
    static func lineAdvance(
        of line: CTLine, at location: Int, in attributedString: NSAttributedString
    ) -> CGFloat {
        lineAdvance(
            metrics: HwpDrawnTextLayout.lineMetrics(of: line, in: attributedString),
            at: location, in: attributedString
        )
    }

    /// 이미 잰 줄 지표로 낸 `lineAdvance(of:at:in:)` — 렌더의 slight-overflow 한 줄
    /// (`HwpDrawnTextLayout.slightOverflowSingleLine`)이 앵커와 같은 지표 한 벌을 다시 재지 않게.
    static func lineAdvance(
        metrics: HwpDrawnTextLayout.LineMetrics, at location: Int,
        in attributedString: NSAttributedString
    ) -> CGFloat {
        HwpLineSpacingRule.rule(in: attributedString, at: location).advance(
            lineBoxHeight: metrics.boxHeight, textBoxHeight: metrics.textBoxHeight
        )
    }

    /// 줄 `range`와 다음 줄 **사이**의 문단 간격 — 줄이 CT 문단을 끝내면 (마지막 글자가
    /// 문단 구분자) 그 문단의 아래 간격 + 다음 문단의 위 간격. 한 줄 끝(코드 10,
    /// `HwpAttributedStringKey.lineBreak`)은 CT에는 문단 구분자지만 한글에서는 같은
    /// 문단의 줄 나눔이라 간격이 들어가지 않는다 (2026-09-15 한글 12.30 실측: 문단
    /// 위/아래 간격 10pt 문단의 한 줄 끝 앞뒤 줄 전진량이 16pt 그대로).
    ///
    /// 문자열 하나가 CT 문단을 둘 이상 품는 것은 컨테이너 블록이 문단들을 `\n`으로 이은
    /// 경우다 (`HwpCombinedBlockString.combine`) — 문단마다 자기 스타일이 붙어
    /// 있으므로 간격은 **줄 자신의 문단**(아래)과 **다음 줄의 문단**(위)에서 각각 읽는다.
    /// 음수 간격은 0으로 본다 (CT와 같다).
    static func paragraphGap(
        afterLine range: CFRange,
        nextLocation: Int,
        in attributedString: NSAttributedString,
        text: NSString
    ) -> CGFloat {
        let end = range.location + range.length
        guard end > 0, end <= text.length, isParagraphSeparator(text.character(at: end - 1)),
              attributedString.attribute(
                  HwpAttributedStringKey.lineBreak, at: end - 1, effectiveRange: nil
              ) == nil
        else { return 0 }
        let style = HwpLineBreaker.paragraphStyle(in: attributedString, at: range.location)
        let nextStyle = HwpLineBreaker.paragraphStyle(in: attributedString, at: nextLocation)
        let after = max(0, HwpLineBreaker.paragraphCGFloat(.paragraphSpacing, in: style) ?? 0)
        let before = max(
            0, HwpLineBreaker.paragraphCGFloat(.paragraphSpacingBefore, in: nextStyle) ?? 0
        )
        return after + before
    }

    /// CoreText·`NSString.getParagraphStart`의 문단 구분자 — LF·CR·U+2029. 줄 구분자
    /// (U+2028·U+0085)는 문단을 끝내지 않는다.
    static func isParagraphSeparator(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2029
    }
}
