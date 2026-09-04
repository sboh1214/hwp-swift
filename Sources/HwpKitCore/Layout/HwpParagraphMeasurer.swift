import CoreGraphics
import CoreHwp
import Foundation

public extension HwpIndex {
    /// 문단의 paraShape — 문단 id로 찾고, 없으면 id 0으로 폴백한다.
    ///
    /// **nil은 paraShape 표가 통째로 빌 때만 나온다.** id는 `HwpIndex.makeIndex`가
    /// 배열 오프셋으로 매긴 조밀한 값이라 (`idMappings.paraShapeArray`에 id 필드가
    /// 없다) 표가 비어 있지 않으면 id 0이 반드시 있고, 그래서 뒤 폴백이 항상
    /// 걸린다. 즉 nil은 정상 문서가 아니라 손상·조작 DocInfo다.
    ///
    /// 남은 호출부는 전부 간격·여백 조회다 (없으면 0). **조판은 여기가 아니라
    /// `paraShapeOrDefault`를 쓴다** — 아래 참조.
    func paraShape(for paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpParaShape? {
        paraShape(id: UInt32(paragraph.paraHeader.paraShapeId)) ?? paraShape(id: 0)
    }

    /// 문단의 paraShape — 둘 다 없으면 기본값으로 조판한다.
    ///
    /// **`HwpParagraphLayout.layout`에 닿는 경로는 전부 이쪽이다** — 스타일 부착
    /// (`HwpTextRunBuilder.attachParagraphStyle`)과 측정 (`HwpParagraphMeasurer` ·
    /// `HwpPageChromeBuilder` · `HwpPaginator.layout`)이 같은 폴백을 써야 측정이
    /// 부착본을 그대로 framesetting할 수 있다 (#80 조각 3).
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
    /// 글자 모양별 속성 사전 캐시 (소유는 `HwpPaginator`) — 표 셀·글상자·각주가
    /// 본문과 같은 캐시를 쓰게 한다. 멤버와이즈 init의 기본값이 nil이라 캐시를
    /// 넘기지 않는 호출부는 동작이 그대로다.
    var attributeCache: HwpTextAttributeCache?

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
        let builder = HwpTextRunBuilder(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: sizeResolver,
            attributeCache: attributeCache
        )
        let attributed = builder
            .build(paragraph: paragraph, controlReplacements: options.controlReplacements)
        let paraShape = index.paraShapeOrDefault(for: paragraph)
        // 탭 스톱은 인자로 넘기지 않는다 — `build`의 `attachParagraphStyle`이
        // 같은 paraShape·같은 탭으로 만든 스타일을 이미 문자열에 실었고,
        // `layout`은 그 부착본을 그대로 framesetting한다 (#80 조각 3).
        var frame = HwpParagraphLayout().layout(
            attributedString: attributed,
            paraShape: paraShape,
            columnWidth: width
        )
        // 빈 문단은 조판 문자열이 없어 `layout`이 높이 0을 준다 (그쪽 주석 참조).
        // 실물은 한 줄을 차지하므로 글자 모양을 아는 이 계층에서 하한을 건다 —
        // 안 걸면 라인 캐시를 쓰지 않는 측정(글상자·캐시 무효 문단·안전밸브로
        // linesegarray를 폐기한 HWPX 문단)에서 빈 줄이 통째로 사라져 뒤 내용이
        // 한 줄 위로 당겨진다 (#137). 대역 문자열로 재므로 줄 간격 종류·클램프·
        // 문단 간격이 실제 문단과 같은 코드로 계산된다. 줄 프레임은 만들지
        // 않는다 — 그릴 글자가 없고, 합성 프레임은 선택 기하가 조판 문자열
        // 범위를 벗어나게 만든다.
        if attributed.length == 0 {
            frame = HwpParagraphFrame(
                totalHeight: HwpParagraphLayout().layout(
                    attributedString: builder.emptyParagraphProbe(for: paragraph),
                    paraShape: paraShape,
                    columnWidth: width
                ).totalHeight,
                lines: []
            )
        }
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
