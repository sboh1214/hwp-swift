import CoreGraphics
import CoreHwp
import Foundation

/// 다단 밴드 상태·로직 — HwpPaginator에서 추출 (동작 불변).
/// paginator actor가 소유하는 내부 struct로, 단 프레임·채우는 단 index·
/// 밴드 사용량·균형 재배치 입력 같은 밴드 상태 뭉치를 캡슐화하고
/// 리셋 시점을 `open(top:contentFrame:defaultSpacing:)` 한 곳으로 모은다.
/// 문단 배치 전역이 읽고 쓰는 공유 상태 (contentHeightUsed·paragraphAnchorTop)와
/// 페이지 확정 (cacheCurrentPage)·블록 방출 (currentBlocks)은 paginator에 남는다.
struct HwpColumnBandController {
    // MARK: - 상태 (이전 HwpPaginator 저장 프로퍼티)

    /// 현재 단 정의 (`cold` 컨트롤). nil이면 1단.
    var currentColumnDef: CoreHwp.HwpColumn?
    /// 현재 단 밴드의 단 프레임 (페이지 좌표). 비어 있으면 contentFrame 1단.
    var columnFrames: [CGRect] = []
    /// 현재 채우는 단 index
    var columnIndex = 0
    /// 현재 밴드에서 실제 사용된 최대 하단 y — 밴드 종료 시 다음 밴드 시작점
    var bandUsedBottom: CGFloat = 0
    /// 밴드에 들어간 본문 텍스트 블록 (밴드 종료 시 단 균형 재배치용).
    struct BandTextBlock {
        let blockIndex: Int
        let lines: [HwpLineFrame]
        /// 블록 높이가 `lines`의 측정 전진량에서 왔는지 — 저장본 줄 캐시 높이
        /// (`HwpPaginator.height(for:fallback:)`)면 false라, 잔여를 흡수하는 마지막 줄 단위의
        /// 높이는 측정값이 아니다 (#166).
        let heightIsMeasured: Bool
        /// 조각을 폭이 다른 단으로 옮길 때 그 단 폭으로 다시 재는 데 쓰는 문단 모양 —
        /// 측정 높이 블록만 싣는다.
        let paraShape: CoreHwp.HwpParaShape?
        /// 블록이 문단 머리에서 시작하는지 — 쪽·단 경계로 나뉜 문단의 뒤 조각 블록은 false다.
        /// 블록 전체를 옮겨 다시 잴 때 문단(한 줄 넘침 규칙을 따른다)과 조각(건너뛴다)을 가른다.
        let startsParagraph: Bool
    }

    var bandTextBlocks: [BandTextBlock] = []
    /// 밴드에 텍스트 외 블록(표/개체/placeholder)이 있으면 균형 재배치를 하지 않는다
    var bandHasNonTextContent = false
    /// 밴드 마지막 줄의 줄 간격 (pt). 한글은 단 정의로 밴드를 닫을 때 이만큼
    /// 띄우고 다음 밴드를 연다 (Column PrvImage 실측: 밴드 간 첫 줄 시작 간격
    /// = 줄 전진량 + 줄 간격, ±1pt).
    var bandTrailingLineSpacing: CGFloat = 0

    // MARK: - 조회

    /// 현재 채우는 단의 프레임. 밴드가 아직 없으면 콘텐츠 전체.
    func currentColumnFrame(contentFrame: CGRect) -> CGRect {
        columnFrames.indices.contains(columnIndex)
            ? columnFrames[columnIndex]
            : contentFrame
    }

    // MARK: - 사용량·전진·리셋

    /// 현재 단의 사용량을 밴드 하단 추적에 반영한다.
    mutating func markUsage(contentHeightUsed: CGFloat, contentFrame: CGRect) {
        bandUsedBottom = max(
            bandUsedBottom,
            currentColumnFrame(contentFrame: contentFrame).minY + contentHeightUsed
        )
    }

    /// top에서 시작하는 새 단 밴드를 연다 — 밴드 상태 리셋의 단일 지점
    /// (paginator.openColumnBand와 cacheCurrentPage의 새 페이지 리셋이 모두
    /// 여기로 온다).
    ///
    /// 기존 openColumnBand의 리셋 순서 고정: columnFrames 재계산 →
    /// columnIndex = 0 → (공유 상태 contentHeightUsed = 0·
    /// paragraphAnchorTop = top은 paginator.openColumnBand가 이어서 수행)
    /// → bandUsedBottom = top → bandTextBlocks = [] →
    /// bandHasNonTextContent = false → bandTrailingLineSpacing = 0.
    /// 상호 의존 없는 단순 대입이라 공유 상태 두 개를 뒤로 빼도 결과는 동일하다.
    mutating func open(top: CGFloat, contentFrame: CGRect, defaultSpacing: CGFloat) {
        let area = CGRect(
            x: contentFrame.minX,
            y: top,
            width: contentFrame.width,
            height: max(1, contentFrame.maxY - top)
        )
        columnFrames = HwpPageGeometry.columnFrames(
            in: area,
            column: currentColumnDef,
            defaultSpacing: defaultSpacing
        )
        columnIndex = 0
        bandUsedBottom = top
        bandTextBlocks = []
        bandHasNonTextContent = false
        bandTrailingLineSpacing = 0
    }

    /// 다음 단이 있으면 columnIndex를 전진시키고 true. 마지막 단이면 false —
    /// 호출자 (paginator.advanceColumn)가 새 페이지를 연다.
    mutating func advanceToNextColumn() -> Bool {
        guard columnIndex + 1 < columnFrames.count else { return false }
        columnIndex += 1
        return true
    }

    /// 밴드 마지막 줄의 줄 간격을 기록한다 (단 정의 밴드 마감 시 다음 밴드
    /// 시작 여백으로 사용). 라인 캐시가 없으면 이전 값을 유지하지 않고 0으로 둔다.
    mutating func updateTrailingSpacing(for paragraph: CoreHwp.HwpParagraph) {
        if let last = paragraph.paraLineSeg.paraLineSegInternalArray.last,
           last.lineSpacing >= 0
        {
            bandTrailingLineSpacing = HwpUnits.points(fromHwpUnit: last.lineSpacing)
        } else {
            bandTrailingLineSpacing = 0
        }
    }

    // MARK: - 단 균형 재배치 (플랜 산출 — currentBlocks 적용은 paginator)

    /// 재배치 플랜: 교체될 기존 블록 index 집합 + 단별로 조립된 새 블록.
    struct RebalancePlan {
        let replacedBlockIndices: Set<Int>
        let newBlocks: [AnyHwpBlock]
        let maxBottom: CGFloat
    }

    /// 밴드에 라인 단위로 흩어 놓을 텍스트 조각
    private struct BandLineUnit {
        let blockIndex: Int
        let range: NSRange
        let height: CGFloat
        /// `height`가 측정 줄 전진량인지 — 아니면(캐시 높이 블록의 잔여·평균 폴백) 이 단위를
        /// 담은 조각에는 측정 줄 조각 표식을 달지 않는다 (#166).
        let heightIsMeasured: Bool
        let paraShape: CoreHwp.HwpParaShape?
        let startsParagraph: Bool
    }

    /// 같은 블록의 연속 단위를 합친 조각 — 한 단에 놓일 블록 하나.
    private struct MergedUnit {
        let blockIndex: Int
        var range: NSRange
        var height: CGFloat
        var heightIsMeasured: Bool
        var count = 1
        let paraShape: CoreHwp.HwpParaShape?
        let startsParagraph: Bool

        init(_ unit: BandLineUnit) {
            blockIndex = unit.blockIndex
            range = unit.range
            height = unit.height
            heightIsMeasured = unit.heightIsMeasured
            paraShape = unit.paraShape
            startsParagraph = unit.startsParagraph
        }

        mutating func merge(_ unit: BandLineUnit) {
            range = NSUnionRange(range, unit.range)
            height += unit.height
            heightIsMeasured = heightIsMeasured && unit.heightIsMeasured
            count += 1
        }
    }

    /// 첫 단에만 쌓인 밴드 텍스트를 라인 단위로 모든 단에 균등 재배치하는
    /// 플랜을 만든다. 라인 조각이 2개 미만이면 nil (재배치 없음 — 기존
    /// rebalanceColumnBand의 `guard units.count > 1` 조기 반환과 동일).
    func rebalancePlan(currentBlocks: [AnyHwpBlock]) -> RebalancePlan? {
        let units = bandLineUnits(currentBlocks: currentBlocks)
        guard units.count > 1 else { return nil }
        let result = balancedBlocks(from: units, currentBlocks: currentBlocks)
        return RebalancePlan(
            replacedBlockIndices: Set(bandTextBlocks.map(\.blockIndex)),
            newBlocks: result.blocks,
            maxBottom: result.maxBottom
        )
    }

    /// 밴드 텍스트 블록들을 라인 단위 조각 목록으로 푼다.
    private func bandLineUnits(currentBlocks: [AnyHwpBlock]) -> [BandLineUnit] {
        var units: [BandLineUnit] = []
        for entry in bandTextBlocks {
            guard currentBlocks.indices.contains(entry.blockIndex),
                  let attributed = currentBlocks[entry.blockIndex].attributedString
            else { continue }
            let blockHeight = currentBlocks[entry.blockIndex].frame.height
            if entry.lines.count > 1 {
                // 라인별 실제 전진량(다음 라인 origin.y 델타 — baseline 상대라 델타가
                // 곧 advance)으로 단위를 만든다. 평균(blockHeight/개수)은 혼합 높이
                // 라인에서 큰 라인보다 짧은 프레임을 배정할 수 있다 (#4). 마지막
                // 라인이 잔여(후행 간격 포함)를 흡수해 총합 = blockHeight를 보존한다.
                // origin이 비단조(캐시 열화)면 평균으로 폴백한다.
                let lines = entry.lines
                let strictlyIncreasing = zip(lines, lines.dropFirst())
                    .allSatisfy { $0.origin.y < $1.origin.y }
                let average = blockHeight / CGFloat(lines.count)
                for (lineIndex, line) in lines.enumerated() {
                    let advance: CGFloat = if !strictlyIncreasing {
                        average
                    } else if lineIndex + 1 < lines.count {
                        lines[lineIndex + 1].origin.y - line.origin.y
                    } else {
                        blockHeight - line.origin.y
                    }
                    // 앞 줄들의 전진량은 원점 델타(측정)이고, 마지막 줄(잔여)과 평균 폴백은
                    // 블록 높이의 출처를 따른다 (#166).
                    let isMeasured = strictlyIncreasing && lineIndex + 1 < lines.count
                        || entry.heightIsMeasured
                    units.append(BandLineUnit(
                        blockIndex: entry.blockIndex,
                        range: line.attributedRange,
                        height: max(1, advance),
                        heightIsMeasured: isMeasured,
                        paraShape: entry.paraShape,
                        startsParagraph: entry.startsParagraph
                    ))
                }
            } else {
                units.append(BandLineUnit(
                    blockIndex: entry.blockIndex,
                    range: NSRange(location: 0, length: attributed.length),
                    height: blockHeight,
                    heightIsMeasured: entry.heightIsMeasured,
                    paraShape: entry.paraShape,
                    startsParagraph: entry.startsParagraph
                ))
            }
        }
        return units
    }

    /// 라인 조각을 단별로 균등 분배해 새 텍스트 블록으로 조립한다.
    private func balancedBlocks(
        from units: [BandLineUnit],
        currentBlocks: [AnyHwpBlock]
    ) -> (blocks: [AnyHwpBlock], maxBottom: CGFloat) {
        let columnCount = columnFrames.count
        let perColumn = Int((Double(units.count) / Double(columnCount)).rounded(.up))
        var newBlocks: [AnyHwpBlock] = []
        var maxBottom = columnFrames[0].minY
        var unitIndex = 0
        for column in 0 ..< columnCount {
            var cursorY = columnFrames[column].minY
            var taken = 0
            while unitIndex < units.count, taken < perColumn {
                // 같은 블록의 연속 라인은 한 조각으로 병합한다.
                var merged = MergedUnit(units[unitIndex])
                unitIndex += 1
                taken += 1
                while unitIndex < units.count, taken < perColumn,
                      units[unitIndex].blockIndex == merged.blockIndex
                {
                    merged.merge(units[unitIndex])
                    unitIndex += 1
                    taken += 1
                }
                let original = currentBlocks[merged.blockIndex]
                guard let attributed = original.attributedString else { continue }
                let fragment = rebalancedFragment(
                    merged, of: attributed, measuredWidth: original.frame.width,
                    columnWidth: columnFrames[column].width
                )
                newBlocks.append(AnyHwpBlock(
                    frame: CGRect(
                        x: columnFrames[column].minX,
                        y: cursorY,
                        width: columnFrames[column].width,
                        height: fragment.height
                    ),
                    kind: .text,
                    attributedString: NSAttributedString(attributedString: fragment.text),
                    hyperlinkURL: original.hyperlinkURL,
                    source: original.source
                ))
                cursorY += fragment.height
            }
            maxBottom = max(maxBottom, cursorY)
            if unitIndex >= units.count {
                break
            }
        }
        return (newBlocks, maxBottom)
    }

    /// 단에 놓을 조각 문자열과 높이. 블록 첫머리가 아닌 조각은 이어지는 조각 — 첫 줄
    /// 들여쓰기를 둘째 줄에 맞춘다(`continuationFragment`).
    ///
    /// 조각 높이가 측정 줄 전진량의 합이면 렌더러가 그 줄 수 그대로 그려야 한다 — 측정 줄
    /// 조각 표식 (#166). 캐시 높이 블록의 잔여 줄을 담은 조각은 종전대로 둔다. 줄은 원래
    /// 블록의 단 폭(첫 단)으로 쟀으므로, 측정 높이 조각이 **폭이 다른 단**으로 옮겨지면 그 단
    /// 폭으로 다시 재어 높이와 줄 수를 그 줄바꿈으로 잡는다 (PR 리뷰 — 표식은 접힘만 막아
    /// 넓은 단에서는 줄이 합쳐져 상자 아래가 비고 좁은 단에서는 줄이 늘어 넘쳤다; 흐름 분할의
    /// `HwpPaginator.remeasureRemainderIfNeeded`와 같은 처방). 다시 잰 높이는 `layout`의
    /// 높이에서 문단 위 간격(밴드 커서가 이미 소비)을 뺀 텍스트 몫이다. 문단 모양을 모르는
    /// 블록(캐시 높이 블록은 싣지 않는다)은 잰 줄로 두고 좁은 단은 실제 줄바꿈으로 판정한다
    /// (`measuredLineFragment`, 폭 허용 오차 없음).
    private func rebalancedFragment(
        _ merged: MergedUnit,
        of attributed: NSAttributedString,
        measuredWidth: CGFloat,
        columnWidth: CGFloat
    ) -> (text: NSAttributedString, height: CGFloat) {
        let isWholeBlock = merged.range.location == 0
            && NSMaxRange(merged.range) == attributed.length
        let remeasures = merged.heightIsMeasured && columnWidth != measuredWidth
            && merged.paraShape != nil
        // 자르지도 다시 재지도 않는 블록은 문자열·높이를 그대로 둔다 — 쪽·단 경계로 나뉜 문단의
        // 뒤 조각 블록(줄 목록 없는 단위 하나)이 제자리에 남을 때 표식을 다시 판정하면 줄 수를
        // 몰라(단위 1개) 벗겨져 #166 증상이 되살아난다 (PR 리뷰, HEAD의 잔여 결함).
        if isWholeBlock, !remeasures {
            return (attributed, merged.height)
        }
        let base = HwpParagraphLayout.continuationFragment(of: attributed, range: merged.range)
        var lineCount = merged.count
        var height = merged.height
        var width = measuredWidth
        if remeasures, let paraShape = merged.paraShape {
            // 문단 머리에서 시작하는 블록 전체(문단)는 문단 단위 한 줄 규칙을 따라 재고, 조각
            // (블록의 일부, 또는 쪽·단 경계로 나뉜 문단의 뒤 조각 블록)은 표식을 단 채로 재어
            // 그 규칙을 건너뛴다 — 조각을 접으면 한글의 줄바꿈과 갈린다. 문단 지표(마지막 줄
            // 높이·줄 뒤 간격)는 블록 전체 문자열로 잰다.
            let plain = HwpParagraphLayout.strippingMeasuredLineMarker(base)
            let frame = HwpParagraphLayout().layout(
                attributedString: isWholeBlock && merged.startsParagraph
                    ? plain : HwpParagraphLayout.markedAsMeasuredLineFragment(plain),
                paraShape: paraShape, columnWidth: columnWidth,
                metricsReference: attributed
            )
            if !frame.lines.isEmpty {
                // 문단 위 간격은 밴드 커서가 이미 소비했고(0 하한은 `authoredBeforeGap`과 같다),
                // 문단 아래 간격은 문단 끝을 담은 조각의 몫이다 — 원래 단위 높이도 마지막 줄
                // 단위만 잔여(아래 간격 포함)를 흡수한다 (PR 리뷰).
                let metrics = HwpParagraphLayout.ParagraphMetrics(
                    paraShape: paraShape, attributedString: attributed
                )
                let reachesEnd = NSMaxRange(merged.range) == attributed.length
                lineCount = frame.lines.count
                height = max(1, frame.totalHeight - max(0, metrics.paragraphSpacingBefore)
                    - (reachesEnd ? 0 : metrics.paragraphSpacing))
                width = columnWidth
            }
        }
        let text = HwpParagraphLayout.measuredLineFragment(
            base,
            heightIsMeasured: merged.heightIsMeasured,
            measuredLineCount: lineCount,
            measuredWidth: width,
            columnWidth: columnWidth
        )
        return (text, height)
    }
}
