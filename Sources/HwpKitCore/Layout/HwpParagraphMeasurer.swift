import CoreGraphics
import CoreHwp
import Foundation

public extension HwpIndex {
    /// 문단의 paraShape — 문단 id로 찾고, 없으면 id 0으로 폴백한다.
    /// 둘 다 없을 때의 의미는 호출부마다 다르므로 (빈 프레임 반환/간격 0/
    /// 스타일 생략) optional을 그대로 돌려준다.
    func paraShape(for paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpParaShape? {
        paraShape(id: UInt32(paragraph.paraHeader.paraShapeId)) ?? paraShape(id: 0)
    }

    /// 문단의 paraShape — 둘 다 없으면 기본값으로 조판한다 (측정 경로용).
    func paraShapeOrDefault(for paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpParaShape {
        paraShape(for: paragraph) ?? CoreHwp.HwpParaShape()
    }
}

/// 문단 측정 공통 코어 — build → paraShape 해석 → CT layout → 캐시 높이 훅.
/// 표 셀 (HwpTableLayout)·글상자 (HwpTextboxLayout)·각주 (HwpFootnoteLayout,
/// HwpPaginator.measuredFootnoteHeight)가 각자 복제하던 패턴의 단일 소스.
struct HwpParagraphMeasurer {
    let index: HwpIndex
    let fontResolver: HwpFontResolver
    var sizeResolver: HwpObjectSizeResolver?

    /// 호출부별 차이를 보존하는 훅.
    struct Options {
        /// extended 컨트롤 마커 (U+FFFC) 치환 — 각주 자동 번호 등.
        var controlReplacements: [Int: HwpControlMarkerReplacement] = [:]
        /// 참: 저장본 라인 캐시 높이가 유효하면 CT 높이 대신 쓴다 (표 셀·각주 —
        /// 폰트 대체로 CT 줄 수가 부풀지 않게). 글상자는 거짓 — CT 측정 그대로.
        var preferCachedHeight = false
        /// 참: 문단 위 간격 절반을 항상 가산한다 (표 셀 — CT는 프레임 첫 문단에
        /// paragraphSpacingBefore를 적용하지 않으므로, 문단별 개별 조판인 셀은
        /// 직접 더한다. 렌더 배치에서 같은 값만큼 문단 상단을 내린다).
        var addHalfSpacingBefore = false
    }

    struct Result {
        let attributed: NSAttributedString
        let frame: HwpParagraphFrame
        /// 라인 캐시 높이를 썼는지 (표 셀의 allCached 집계용)
        let usedCachedHeight: Bool
    }

    func measure(
        _ paragraph: CoreHwp.HwpParagraph,
        width: CGFloat,
        options: Options = Options()
    ) -> Result {
        let attributed = HwpTextRunBuilder(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: sizeResolver
        )
        .build(paragraph: paragraph, controlReplacements: options.controlReplacements)
        let paraShape = index.paraShapeOrDefault(for: paragraph)
        var frame = HwpParagraphLayout().layout(
            attributedString: attributed,
            paraShape: paraShape,
            columnWidth: width,
            tabStops: index.textTabs(for: paraShape)
        )
        // 표 43 여백 계열과 같은 1/2 단위 (HwpParagraphMetrics와 동일).
        let spacingBefore = options.addHalfSpacingBefore
            ? HwpUnits.points(fromHwpUnit: paraShape.paragraphSpacingTop) / 2
            : 0
        let spacingAfter = options.addHalfSpacingBefore
            ? HwpUnits.points(fromHwpUnit: paraShape.paragraphSpacingBottom) / 2
            : 0
        var usedCachedHeight = false
        // 캐시 높이는 라인 범위만 담으므로 CT 경로(totalHeight = before + lines +
        // after)와 같아지도록 양쪽 간격을 더한다 — 표 셀(addHalfSpacingBefore)만.
        // 각주는 이어지는 문단이 간격 없이 붙는 실측 규약이라 캐시 높이 그대로 둔다.
        // 비-캐시 경로는 totalHeight가 이미 간격을 포함한다 (P2).
        if options.preferCachedHeight,
           let cachedHeight = HwpParagraphLayout.cachedParagraphHeight(paragraph)
        {
            frame = HwpParagraphFrame(
                totalHeight: cachedHeight + spacingBefore + spacingAfter,
                lines: frame.lines
            )
            usedCachedHeight = true
        }
        return Result(
            attributed: attributed,
            frame: frame,
            usedCachedHeight: usedCachedHeight
        )
    }
}
