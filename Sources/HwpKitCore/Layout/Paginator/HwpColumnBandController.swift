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
    /// 밴드에 들어간 본문 텍스트 블록 (밴드 종료 시 단 균형 재배치용)
    var bandTextBlocks: [(blockIndex: Int, lines: [HwpLineFrame])] = []
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
                let lineHeight = blockHeight / CGFloat(entry.lines.count)
                for line in entry.lines {
                    units.append(BandLineUnit(
                        blockIndex: entry.blockIndex,
                        range: line.attributedRange,
                        height: lineHeight
                    ))
                }
            } else {
                units.append(BandLineUnit(
                    blockIndex: entry.blockIndex,
                    range: NSRange(location: 0, length: attributed.length),
                    height: blockHeight
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
                let blockIndex = units[unitIndex].blockIndex
                var mergedRange = units[unitIndex].range
                var mergedHeight = units[unitIndex].height
                unitIndex += 1
                taken += 1
                while unitIndex < units.count, taken < perColumn,
                      units[unitIndex].blockIndex == blockIndex
                {
                    mergedRange = NSUnionRange(mergedRange, units[unitIndex].range)
                    mergedHeight += units[unitIndex].height
                    unitIndex += 1
                    taken += 1
                }
                let original = currentBlocks[blockIndex]
                guard let attributed = original.attributedString else { continue }
                let sub = attributed.attributedSubstring(from: mergedRange)
                newBlocks.append(AnyHwpBlock(
                    frame: CGRect(
                        x: columnFrames[column].minX,
                        y: cursorY,
                        width: columnFrames[column].width,
                        height: mergedHeight
                    ),
                    kind: .text,
                    attributedString: NSAttributedString(attributedString: sub),
                    hyperlinkURL: original.hyperlinkURL,
                    source: original.source
                ))
                cursorY += mergedHeight
            }
            maxBottom = max(maxBottom, cursorY)
            if unitIndex >= units.count {
                break
            }
        }
        return (newBlocks, maxBottom)
    }
}
