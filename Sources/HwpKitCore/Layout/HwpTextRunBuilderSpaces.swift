import CoreHwp
import CoreText
import Foundation

/// 빈칸 한 자의 조판 폭을 정하는 글자 모양 값 (#249) — 슬롯별 크기와 장평.
///
/// 조판은 빈칸(U+0020)을 라틴 chunk 글자로 그리고(한글은 앞 글자 항목의 글꼴로 그린다), 한글은
/// 그 **폭을 라틴 슬롯에서 정하지 않는다**. 한글 12.30.0 build 6523 실측(2026-10-03, `CharShape`
/// HWPX 기반 합성 문서 20pt를 PDF로 내보내 빈칸 원점 → 다음 글자 원점 거리를 읽었다 — 600dpi 장치
/// 단위 0.12pt로 양자화된 값이다)으로 확정한 규칙:
/// - **고정 폭**(`fixedWidth`): '글꼴에 어울리는 빈칸'(표 35 bit 25)이 꺼진 빈칸은 한글 슬롯
///   글자 크기 × 0.5 × 한글 장평이다 — 빈칸 앞뒤 글자(한글·라틴·숫자·한자·기호·일어·구두점·
///   연속 빈칸·줄 시작)와 무관하고, 라틴 장평·다른 슬롯의 상대 크기도 무관하다.
/// - **글꼴 폭**(`fontWidth`): 그 옵션이 켜진 빈칸은 라틴 슬롯 글꼴의 빈칸 글리프 폭(em)을
///   **빈칸이 배정된 슬롯**의 크기·장평으로 키운 값이다. 배정 슬롯은 같은 글자 모양 run 안의
///   앞 글자의 슬롯이고(앞이 빈칸이면 그 빈칸의 배정을 물려받는다), run·문단 시작과 제어 문자
///   뒤는 라틴이다(실측: 한 줄 끝 뒤 `가나↵ 다라`·묶음 빈칸 뒤의 빈칸이 라틴 슬롯 폭; 탭 뒤는
///   표본의 앞 글자가 라틴이라 구별되지 않았다) — 한글 50%·라틴 Menlo 100%의 `가나 ab`는 Menlo
///   빈칸 0.6em × 10pt = 6pt, `ab cd`는 12pt.
/// - MS 워드 호환 문서는 옵션이 꺼져 있어도 앞뒤가 모두 라틴 부류 글자인 빈칸만 글꼴 폭이다
///   (`usesFontWidth`·`isMsWordLatinNeighbor`). 한글 2007 호환 문서는 한글 문서와 같다.
/// - 묶음 빈칸(제어 문자 30)은 문서 갈래·옵션과 무관하게 고정 폭이고, 고정폭 빈칸(31)은 그
///   절반(한글 슬롯 크기 × 0.25 × 한글 장평)이다 — 둘 다 U+00A0으로 조판되므로 고정폭 빈칸은
///   표식(`HwpAttributedStringKey.fixedWidthSpace`)으로 가른다.
///
/// **자간은 이 수정의 축이 아니라 종전 동작을 그대로 둔다** — 고정 폭 빈칸에는 자간이 없고(빈칸
/// kern을 폭으로 덮어쓴다), 글꼴 폭 빈칸은 run의 자간 kern(라틴 크기 × 라틴 자간 %,
/// `latinSpacingKern`)을 지닌다. 한글은 보통·고정폭 빈칸에 라틴 자간을 **폭의 %로** 붙이지만(같은
/// 실측: 라틴 자간 20%면 고정 폭 10pt → 12pt, 글꼴 폭 6pt → 7.2pt, 묶음 빈칸은 그대로) 그것은 글자
/// 자간과 한 모델이다 — 한글은 글자 자간도 **글자 전진량의 %**로 붙이는데(라틴 `a` 11.4pt → 자간
/// 20%에 13.68pt) 조판은 글자 크기의 %(`HwpTextRunBuilder.attributes(for:script:)`)로 붙인다.
/// 빈칸에만 한글 모델을 넣으면 음수 자간 문서에서 빈칸만 좁아지고 라틴 글자·따옴표는 여전히
/// 한글보다 좁아 줄 폭이 한글보다 짧아진다(실측: `noori` 2쪽 자간 −7% 줄이 한 글자를 더 담아
/// 줄바꿈이 한글과 갈렸다). 그래서 둘을 함께 바꾼다 (후속 이슈).
struct HwpSpaceWidthMetrics: Equatable {
    /// 빈칸의 종류 — 폭 규칙이 갈린다.
    enum Kind: Equatable {
        /// 보통 빈칸 (U+0020).
        case ordinary
        /// 묶음 빈칸 (제어 문자 30 → U+00A0).
        case nonBreaking
        /// 고정폭 빈칸 (제어 문자 31 → U+00A0 + 표식).
        case fixedWidth
    }

    /// 슬롯별 글자 크기 (pt, 기본 크기 × 상대 크기) — `HwpScript.slotIndex` 순서.
    let slotSizes: [CGFloat]
    /// 슬롯별 장평 (배율, 1 = 100%).
    let slotScales: [CGFloat]
    /// 빈칸 run이 지니던 자간 kern (pt, 라틴 크기 × 라틴 자간 %) — `attributes(for:script:)`가
    /// 라틴 chunk에 싣는 값과 같다. 글꼴 폭 빈칸만 종전처럼 이것을 지닌다.
    let latinSpacingKern: CGFloat

    init(shape: CoreHwp.HwpCharShape) {
        let base = HwpUnits.points(fromHwpUnit: shape.baseSize)
        slotSizes = (0 ..< 7).map { slot in
            base * CGFloat(Self.value(at: slot, in: shape.faceRelativeSize, default: 100)) / 100
        }
        slotScales = (0 ..< 7).map { slot in
            CGFloat(Self.value(at: slot, in: shape.faceScaleX, default: 100)) / 100
        }
        let latin = HwpScript.english.slotIndex
        latinSpacingKern = CGFloat(Self.value(at: latin, in: shape.faceSpacing, default: 0))
            * slotSizes[latin] / 100
    }

    /// 고정 폭 (pt) — 한글 슬롯 크기 × `HwpRenderTuning.Text.fixedSpaceEmRatio` × 한글 장평.
    var fixedWidth: CGFloat {
        let slot = HwpScript.korean.slotIndex
        return slotSizes[slot] * HwpRenderTuning.Text.fixedSpaceEmRatio * slotScales[slot]
    }

    /// 글꼴 폭 (pt) — 라틴 글꼴 빈칸 글리프의 em 폭을 배정 슬롯의 크기·장평으로 키운다.
    func fontWidth(spaceEm: CGFloat, slot: HwpScript) -> CGFloat {
        spaceEm * slotSizes[slot.slotIndex] * slotScales[slot.slotIndex]
    }

    /// 빈칸의 진행 폭 (pt) — `fontWidth`는 보통 빈칸이 글꼴 폭을 쓸 때의 그 폭(nil이면 고정 폭).
    /// 글꼴 폭에만 run 자간 kern(`latinSpacingKern`)이 더해진다 (종전 동작).
    func advance(of kind: Kind, fontWidth: CGFloat? = nil) -> CGFloat {
        switch kind {
        case .ordinary:
            fontWidth.map { $0 + latinSpacingKern } ?? fixedWidth
        case .nonBreaking:
            fixedWidth
        case .fixedWidth:
            fixedWidth / HwpRenderTuning.Text.fixedSpaceEmRatio
                * HwpRenderTuning.Text.fixedWidthSpaceEmRatio
        }
    }

    /// 보통 빈칸이 글꼴 폭을 쓰는가 — '글꼴에 어울리는 빈칸'이 켜졌거나, MS 워드 호환
    /// 문서에서 앞뒤 글자가 **모두** 라틴 부류일 때. 앞뒤가 빈칸·제어 문자·문단 경계면
    /// 라틴 부류가 아니다 (실측: `ab  cd`의 두 빈칸, 줄 시작 ` ab`, 탭·한 줄 끝 뒤 모두 고정 폭).
    /// 이웃은 글자 모양 run 경계를 넘어 실제로 맞닿은 글자다 — `ab` + ` cd`(다른 글자 모양)의
    /// 빈칸도 글꼴 폭이다.
    static func usesFontWidth(
        adjustsToFont: Bool,
        isMsWordDocument: Bool,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?
    ) -> Bool {
        if adjustsToFont {
            return true
        }
        guard isMsWordDocument, let previous, let next else { return false }
        return isMsWordLatinNeighbor(previous) && isMsWordLatinNeighbor(next)
    }

    /// MS 워드 호환 문서에서 빈칸을 글꼴 폭으로 두는 이웃 글자 — Word가 글자마다 라틴
    /// 글꼴(`w:ascii`·`w:hAnsi`)과 동아시아 글꼴(`w:eastAsia`)을 가르는 규칙(ECMA-376 1부
    /// §17.3.2.26)의 라틴 쪽이다. 한글 12.30 실측(2026-10-03, `a X a` 282자 — 글리프가 없어
    /// 잴 수 없던 `₿` 하나를 뺀 281자에서 앞뒤 두 빈칸이 늘 같은 쪽으로 갈렸다):
    /// - 라틴: ASCII 전부, Latin-1 보충의 아래 목록 밖(`À`–`ÿ`·`¢ £ ¥ ¦ © « ¬ ® µ »`), 라틴
    ///   확장, 그리스·키릴·히브리·아랍·태국 문자, 따옴표 `‘ ’ “ ”`.
    /// - 동아시아: Latin-1 보충의 `¡ ¤ § ¨ ª ¯ ° ± ² ³ ´ ¶ · ¸ ¹ º ¼ ½ ¾ ¿ × ÷`(Word가 동아시아
    ///   힌트에서 동아시아 글꼴로 보내는 바로 그 집합 — 무른 하이픈 U+00AD도 같은 목록이다),
    ///   그 밖의 일반 구두점(`‐`–`‗`·`‚ ‛ „ ‟`·`†`–`‾`), U+2070 이후 기호(첨자·통화·문자형·숫자형·
    ///   화살표·수학·괄호 숫자·상자·도형·기타 기호), CJK 기호·한글·가나·한자·전각·반각 형태.
    ///
    /// 측정하지 않은 대역(결합 부호·IPA·로마자 확장 추가·표현형)은 Word 표가 라틴 글꼴로
    /// 보내는 쪽으로 둔다. 한글 자모(U+1100–U+11FF)는 동아시아다.
    static func isMsWordLatinNeighbor(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x21 ... 0x7E:
            true
        case 0xA1 ... 0xFF:
            !msWordEastAsianLatin1.contains(scalar.value)
        case 0x0100 ... 0x10FF, 0x1200 ... 0x1FFF:
            true
        case 0x2018, 0x2019, 0x201C, 0x201D:
            true
        case 0xFB00 ... 0xFDFF, 0xFE70 ... 0xFEFE:
            true
        default:
            false
        }
    }

    /// Latin-1 보충 중 Word가 동아시아 글꼴로 보내는 글자 (`isMsWordLatinNeighbor`).
    static let msWordEastAsianLatin1: Set<UInt32> = Set(
        [0xA1, 0xA4, 0xA7, 0xA8, 0xAA, 0xAD, 0xAF, 0xD7, 0xF7]
            + Array(0xB0 ... 0xB4) + Array(0xB6 ... 0xBA) + Array(0xBC ... 0xBF)
    )

    private static func value<T>(at index: Int, in array: [T], default fallback: T) -> T {
        index < array.count ? array[index] : fallback
    }
}

/// 빈칸 폭 패스 (#249) — 조판 문자열이 완성된 **뒤에** 빈칸마다 앞뒤 글자를 보고 폭을 정한다.
///
/// chunk(`append`) 단위로는 정할 수 없다: 빈칸은 늘 라틴 chunk에 들어가는데(`HwpScript.detect`의
/// 기본값) 배정 슬롯은 **앞** chunk의 마지막 글자가, MS 워드 호환 문서의 글꼴 폭 여부는 **뒤**
/// chunk의 첫 글자가 정한다.
extension HwpTextRunBuilder {
    /// `range` 안의 보통 빈칸(U+0020)과 묶음·고정폭 빈칸(U+00A0)에 한글의 폭을 kern으로
    /// 준다 (`HwpSpaceWidthMetrics`). 빈칸 run의 기존 kern(글자 모양 자간)을 폭으로 **덮어쓴다** —
    /// 글꼴 폭 빈칸만 그 자간을 폭에 다시 더한다 (종전 동작, `HwpSpaceWidthMetrics` 문서).
    ///
    /// `range` 밖의 글자는 이웃으로 보지 않는다 — 문단 머리(글머리표·문단 번호 라벨)는 본문
    /// 글자가 아니므로 본문 첫 빈칸은 줄 시작과 같다. 건너뛰는 빈칸: 빈 줄 앵커(폭이 화면에
    /// 드러나지 않고 속성을 허용 목록으로 깎는다), 문단 번호 라벨의 거리 빈칸(정의가 정한 폭을
    /// kern으로 이미 실었다), 컨트롤 치환 run(각주 번호 등), 빈칸 글리프가 없는 글꼴.
    ///
    /// **속성 run 단위로 돈다** — 글꼴·글자 모양·빈칸 글리프 폭을 run마다 한 번만 구하고(글자 모양
    /// 값은 id별로 한 번), kern은 바뀌는 빈칸에만 쓴다. 빈칸마다 속성 사전을 꺼내던 첫 구현은 글꼴
    /// 폭 판정이 도는 문서(MS 워드 호환·'글꼴에 어울리는 빈칸')의 라틴 본문 조판을 1.6~1.9배로
    /// 늘렸고, 폭이 같은데도 부동소수 잔차(1e-16) kern을 써 run을 쪼갰다 (#249 리뷰). run 단위로
    /// 바꾼 뒤 라틴 문단 2,000개 build는 main 대비 +5%(MS 워드)·+13%(글꼴 빈칸)이다.
    func applySpaceWidths(to output: NSMutableAttributedString, in range: NSRange? = nil) {
        let range = range ?? NSRange(location: 0, length: output.length)
        guard range.length > 0 else { return }
        let text = output.string as NSString
        var context = SpacePassContext(
            output: output, text: text, range: range,
            isMsWordDocument: index.compatibleDocumentTarget == .msWord
        )
        var kerns: [(position: Int, kern: CGFloat)] = []
        output.enumerateAttributes(in: range) { attributes, run, _ in
            guard let runSpaces = spaceRun(attributes: attributes, context: &context) else {
                return
            }
            for position in run.location ..< NSMaxRange(run) {
                let unit = text.character(at: position)
                guard unit == 0x20 || unit == 0xA0,
                      let kern = spaceKern(
                          at: position, unit: unit, run: runSpaces, context: &context
                      )
                else { continue }
                kerns.append((position, kern))
            }
        }
        for (position, kern) in kerns {
            output.addAttribute(
                kCTKernAttributeName as NSAttributedString.Key,
                value: NSNumber(value: Double(kern)),
                range: NSRange(location: position, length: 1)
            )
        }
    }

    /// 한 패스가 run 사이에 나르는 상태 — 글자 모양 값 캐시와 직전 빈칸의 배정.
    struct SpacePassContext {
        let output: NSAttributedString
        let text: NSString
        let range: NSRange
        let isMsWordDocument: Bool
        var metrics: [UInt32?: (shape: CoreHwp.HwpCharShape, metrics: HwpSpaceWidthMetrics)] = [:]
        /// 직전 빈칸의 배정 — 연속 빈칸이 배정을 물려받을 때 앞 빈칸들을 다시 거슬러 올라가지
        /// 않게 한다 (빈칸 N개짜리 문단이 O(N²)이 되지 않는다).
        var memo: AssignedSlotMemo?
    }

    /// 배정 슬롯을 이미 구한 빈칸 (`assignedSlot`의 역탐색 지름길).
    struct AssignedSlotMemo {
        let position: Int
        let slot: HwpScript
    }

    /// 빈칸을 품을 수 있는 run 하나의 값 — run마다 한 번 구한다.
    struct SpaceRun {
        let font: CTFont
        let shapeKey: NSNumber?
        let shape: CoreHwp.HwpCharShape
        let metrics: HwpSpaceWidthMetrics
        let isFixedWidthSpace: Bool
        /// run이 이미 지닌 kern (자간) — 같은 값이면 쓰지 않는다.
        let existingKern: CGFloat
        /// U+0020·U+00A0 글리프의 진행 폭 (장평 행렬 포함, 글리프가 없으면 nil).
        let spaceAdvance: CGFloat?
        let nonBreakingAdvance: CGFloat?
    }

    /// 빈칸 폭을 줄 run이면 그 값을, 건너뛸 run이면 nil을 준다.
    private func spaceRun(
        attributes: [NSAttributedString.Key: Any], context: inout SpacePassContext
    ) -> SpaceRun? {
        guard attributes[HwpAttributedStringKey.emptyLineAnchor] == nil,
              attributes[HwpAttributedStringKey.numberingLabel] == nil,
              attributes[HwpAttributedStringKey.controlIndex] == nil,
              let fontValue = attributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        let font = fontValue as! CTFont // swiftlint:disable:this force_cast
        let shapeKey = attributes[HwpAttributedStringKey.charShapeId] as? NSNumber
        let resolved: (shape: CoreHwp.HwpCharShape, metrics: HwpSpaceWidthMetrics)
        if let cached = context.metrics[shapeKey?.uint32Value] {
            resolved = cached
        } else {
            let shape = shapeKey.flatMap { index.charShape(id: $0.uint32Value) }
                ?? CoreHwp.HwpCharShape()
            resolved = (shape, HwpSpaceWidthMetrics(shape: shape))
            context.metrics[shapeKey?.uint32Value] = resolved
        }
        return SpaceRun(
            font: font, shapeKey: shapeKey, shape: resolved.shape, metrics: resolved.metrics,
            isFixedWidthSpace: attributes[HwpAttributedStringKey.fixedWidthSpace] != nil,
            existingKern: CGFloat(
                (attributes[kCTKernAttributeName as NSAttributedString.Key] as? NSNumber)?
                    .doubleValue ?? 0
            ),
            spaceAdvance: Self.spaceGlyphAdvance(of: 0x20, in: font),
            nonBreakingAdvance: Self.spaceGlyphAdvance(of: 0xA0, in: font)
        )
    }

    /// 빈칸 하나의 kern — 이미 그 값이면(또는 글리프가 없어 진행 폭을 모르면) nil.
    private func spaceKern(
        at position: Int, unit: UniChar, run: SpaceRun, context: inout SpacePassContext
    ) -> CGFloat? {
        // 글리프가 없으면 CoreText가 다른 글꼴로 대체해 진행 폭을 알 수 없다 — 종전대로 둔다.
        guard let glyphAdvance = unit == 0x20 ? run.spaceAdvance : run.nonBreakingAdvance
        else { return nil }
        let kind: HwpSpaceWidthMetrics.Kind = if unit == 0x20 {
            .ordinary
        } else if run.isFixedWidthSpace {
            .fixedWidth
        } else {
            .nonBreaking
        }
        var fontWidth: CGFloat?
        if kind == .ordinary,
           HwpSpaceWidthMetrics.usesFontWidth(
               adjustsToFont: run.shape.property.doesAdjustBlank,
               isMsWordDocument: context.isMsWordDocument,
               previous: Self.scalar(before: position, in: context.text, range: context.range),
               next: Self.scalar(after: position, in: context.text, range: context.range)
           )
        {
            // CTFont의 진행 폭에는 장평 행렬이 이미 들어 있다 — 행렬과 크기를 걷어 em으로 되돌린다.
            let scale = CTFontGetSize(run.font) * abs(CTFontGetMatrix(run.font).a)
            if scale > 0 {
                let slot = assignedSlot(
                    at: position, in: context.output, text: context.text, range: context.range,
                    shapeKey: run.shapeKey, memo: context.memo
                )
                context.memo = AssignedSlotMemo(position: position, slot: slot)
                fontWidth = run.metrics.fontWidth(spaceEm: glyphAdvance / scale, slot: slot)
            }
        }
        let kern = run.metrics.advance(of: kind, fontWidth: fontWidth) - glyphAdvance
        // 같은 값을 다시 쓰면 부동소수 잔차가 run을 쪼갠다.
        return abs(kern - run.existingKern) < 0.000_001 ? nil : kern
    }

    /// 글꼴 폭 빈칸이 배정되는 슬롯 — 같은 글자 모양 run 안의 앞 글자의 슬롯 (실측:
    /// `HwpSpaceWidthMetrics` 문서). 앞 빈칸은 그 배정을 물려받고(`가나  다라`의 두 빈칸이
    /// 모두 한글), 형식 문자·결합 부호는 앞 글자에 붙으므로 건너뛴다. run·범위 시작과 제어
    /// 문자(탭·한 줄 끝·컨트롤 마커·묶음 빈칸) 뒤는 라틴이다 (실측: run이 바뀐 ` ab`, 한 줄 끝·
    /// 묶음 빈칸 뒤의 빈칸이 라틴 빈칸 폭 — 탭·컨트롤 마커는 같은 부류로 둔다). 컨트롤 치환
    /// run(각주 번호 `1)` 등)의 글자는 글자로 본다 — 한글이 그 자리를 어떻게 보는지는 재지
    /// 않았다.
    func assignedSlot(
        at position: Int,
        in output: NSAttributedString,
        text: NSString,
        range: NSRange,
        shapeKey: NSNumber?,
        memo: AssignedSlotMemo? = nil
    ) -> HwpScript {
        var cursor = position
        while cursor > range.location {
            cursor -= 1
            let key = output.attribute(
                HwpAttributedStringKey.charShapeId, at: cursor, effectiveRange: nil
            ) as? NSNumber
            guard key == shapeKey else { return .english }
            if text.character(at: cursor) == 0x20 {
                // 같은 글자 모양의 앞 빈칸이 이미 배정을 구했으면 그것이 곧 이 빈칸의 배정이다.
                if let memo, memo.position == cursor {
                    return memo.slot
                }
                continue
            }
            guard let scalar = Self.scalar(endingAt: &cursor, in: text, lowerBound: range.location),
                  !Self.isSpaceControl(scalar)
            else { return .english }
            switch scalar.properties.generalCategory {
            case .format, .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                return HwpScript.detect(from: scalar)
            }
        }
        return .english
    }

    /// 빈칸 이웃·배정에서 글자로 치지 않는 제어 문자 — 탭·한 줄 끝·컨트롤 마커(U+FFFC)·
    /// 묶음 빈칸(U+00A0). 한글에서는 모두 코드 32 미만의 제어 문자다.
    static func isSpaceControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0xA0 || scalar.value == 0xFFFC
    }

    /// `position` 바로 앞 글자 (범위 안, 대리 쌍 복원) — 없거나 제어 문자면 nil.
    static func scalar(before position: Int, in text: NSString, range: NSRange) -> Unicode.Scalar? {
        guard position > range.location else { return nil }
        var cursor = position - 1
        guard let scalar = scalar(endingAt: &cursor, in: text, lowerBound: range.location),
              !isSpaceControl(scalar)
        else { return nil }
        return scalar
    }

    /// `position` 바로 뒤 글자 (범위 안, 대리 쌍 복원) — 없거나 제어 문자면 nil.
    static func scalar(after position: Int, in text: NSString, range: NSRange) -> Unicode.Scalar? {
        let next = position + 1
        guard next < NSMaxRange(range) else { return nil }
        let unit = text.character(at: next)
        var value = UInt32(unit)
        if UTF16.isLeadSurrogate(unit), next + 1 < NSMaxRange(range) {
            let trail = text.character(at: next + 1)
            if UTF16.isTrailSurrogate(trail) {
                value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
            }
        }
        guard let scalar = Unicode.Scalar(value), !isSpaceControl(scalar) else { return nil }
        return scalar
    }

    /// `cursor` 자리에서 끝나는 글자 — 하위 대리면 상위 대리와 묶고 `cursor`를 그 자리로 옮긴다.
    static func scalar(
        endingAt cursor: inout Int, in text: NSString, lowerBound: Int
    ) -> Unicode.Scalar? {
        let unit = text.character(at: cursor)
        var value = UInt32(unit)
        if UTF16.isTrailSurrogate(unit), cursor > lowerBound {
            let lead = text.character(at: cursor - 1)
            if UTF16.isLeadSurrogate(lead) {
                value = 0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(unit) - 0xDC00)
                cursor -= 1
            }
        }
        return Unicode.Scalar(value)
    }

    /// 빈칸 글리프의 진행 폭 (pt, 장평 행렬 포함) — 글꼴에 그 글리프가 없으면 nil.
    static func spaceGlyphAdvance(of character: UniChar, in font: CTFont) -> CGFloat? {
        var character = character
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return nil }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }
}
