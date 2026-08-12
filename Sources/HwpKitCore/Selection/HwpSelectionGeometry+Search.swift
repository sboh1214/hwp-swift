import CoreGraphics
import Foundation

/// 검색(#75)이 필요로 하는 지오메트리 접근. 본체(`HwpSelectionGeometry.swift`)가
/// 이미 SwiftLint `file_length` 경고선에 가까워 별도 파일로 둔다.
///
/// 검색은 선택과 **같은 인스턴스**를 쓴다 — 단위 캐시를 이중화하면 1,030쪽
/// 문서에서 전개본이 두 벌 상주한다.
public extension HwpSelectionGeometry {
    /// 이 지오메트리가 보고 있는 문서의 페이지 수.
    ///
    /// `units(forPage:)`는 범위 밖 인덱스에도 빈 배열을 주므로 그것만으로는
    /// "아직 로드되지 않은 페이지"와 "텍스트가 없는 페이지"가 구분되지 않는다.
    /// 검색은 스캔 범위를 정하려면 이 값이 있어야 한다.
    var pageCount: Int {
        document.pages.count
    }

    /// 한 페이지에 **여러** 선택의 하이라이트를 계산한다.
    ///
    /// `highlightRects(pageIndex:selection:)`을 매치마다 부르면 호출마다 그
    /// 페이지의 단위를 전량 훑어 O(매치 수 × 단위 수)가 된다. 이 오버로드는
    /// 단위와 선택을 **양쪽 다 문서 순서로 훑는 스윕**이라 O(단위 수 + 매치 수)이고,
    /// 줄 조판(`drawnLines`)도 단위당 최대 한 번만 건드린다.
    ///
    /// 반환 rect의 **집합**은 각 선택을 따로 질의한 결과의 합집합과 같다.
    /// 다만 순서는 (단위 → 선택)이라 (선택 → 단위)인 단일 버전과 다르다 —
    /// 하이라이트는 `CGPath`에 모아 한 번에 칠하므로 순서에 의미가 없다.
    func highlightRects(pageIndex: Int, selections: [HwpTextSelection]) -> [CGRect] {
        guard !selections.isEmpty else { return [] }
        let units = units(forPage: pageIndex)
        guard !units.isEmpty else { return [] }

        // 이 페이지에 걸치는 범위만 남기고 문서 순서로 정렬한다. 아래 스윕은
        // start 순 정렬을 전제로 한다.
        let ranges = selections
            .compactMap { selection -> PositionRange? in
                guard !selection.isCollapsed else { return nil }
                let range = selection.range
                guard pageIndex >= range.start.pageIndex,
                      pageIndex <= range.end.pageIndex else { return nil }
                return PositionRange(start: range.start, end: range.end)
            }
            .sorted { $0.start < $1.start }
        guard !ranges.isEmpty else { return [] }

        var rects: [CGRect] = []
        // 이미 지나간 범위의 시작 인덱스. 단위가 문서 순서라 단조 증가한다.
        var firstActive = 0

        for (ordinal, unit) in units.enumerated() {
            let span = UnitSpan(unit: unit, ordinal: ordinal, pageIndex: pageIndex)
            // 끝이 이 단위 시작보다 앞인 범위는 뒤 단위에도 걸리지 않는다.
            while firstActive < ranges.count, ranges[firstActive].end <= span.start {
                firstActive += 1
            }
            rects += highlightRects(for: span, ranges: ranges, from: firstActive)
        }
        return rects
    }

    /// `pageRange` 밖 페이지의 단위 캐시를 버린다.
    ///
    /// 이 클래스에는 축출이 하나도 없었다 — 선택은 사용자가 훑은 페이지만
    /// 만지므로 문제가 없었지만, 검색은 전 문서를 스캔해 1,030쪽 전부의
    /// 단위 배열을 상주시킨다.
    ///
    /// `lineCache`는 건드리지 않는다. 그쪽은 이미 자체 상한(FIFO 512)이 있고,
    /// 단위는 문서가 불변인 한 재계산해도 같은 값이라 `(page, ordinal)` 키가
    /// 그대로 유효하다.
    func evictUnits(keeping pageRange: Range<Int>) {
        unitCache = unitCache.filter { pageRange.contains($0.key) }
    }
}

extension HwpSelectionGeometry {
    /// 정규화된 선택 범위 — 튜플 배열은 `sorted`에서 라벨이 흐려져 struct로 둔다.
    struct PositionRange {
        let start: HwpTextPosition
        let end: HwpTextPosition
    }

    /// 스윕이 보고 있는 단위 하나와 그 문서 위치 구간.
    struct UnitSpan {
        let unit: HwpTextUnit
        let ordinal: Int
        let start: HwpTextPosition
        let end: HwpTextPosition

        init(unit: HwpTextUnit, ordinal: Int, pageIndex: Int) {
            self.unit = unit
            self.ordinal = ordinal
            start = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex, characterOffset: 0
            )
            end = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex,
                characterOffset: unit.attributedString.length
            )
        }
    }

    /// 단위 하나에 걸리는 범위들의 하이라이트 rect. 줄 조판(`drawnLines`)은
    /// 실제로 걸리는 범위가 나올 때까지 미뤄 단위당 최대 한 번만 건드린다.
    func highlightRects(
        for span: UnitSpan, ranges: [PositionRange], from firstActive: Int
    ) -> [CGRect] {
        var rects: [CGRect] = []
        var lines: [HwpDrawnLine]?
        var index = firstActive
        while index < ranges.count, ranges[index].start < span.end {
            let range = ranges[index]
            index += 1
            guard span.end > range.start, span.start < range.end else { continue }
            let lower = max(range.start, span.start).characterOffset
            let upper = span.start >= range.start && span.end <= range.end
                ? span.unit.attributedString.length
                : min(range.end, span.end).characterOffset
            guard upper > lower else { continue }
            let resolved = lines ?? drawnLines(
                pageIndex: span.start.pageIndex, unitOrdinal: span.ordinal
            )
            lines = resolved
            for line in resolved {
                if let rect = highlightRect(
                    in: line,
                    characterRange: NSRange(location: lower, length: upper - lower)
                ) {
                    rects.append(rect)
                }
            }
        }
        return rects
    }
}
