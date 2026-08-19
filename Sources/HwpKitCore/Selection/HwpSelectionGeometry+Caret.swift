import CoreGraphics
import CoreText
import Foundation

/// 선택 **끝점 캐럿**(폭 0) 지오메트리 — 선택 핸들(#84)이 쓴다.
///
/// 본체(`HwpSelectionGeometry.swift`)가 이미 SwiftLint `type_body_length`
/// 경고 구간이라 별도 파일의 확장으로 둔다 (`+Search`와 같은 이유).
///
/// HwpKitCore에 두는 이유는 캐시다 — `drawnLines(pageIndex:unitOrdinal:)`가
/// 모듈 internal이라, 뷰가 `units(forPage:)` + `HwpDrawnTextLayout.lines`로
/// 직접 조판하면 FIFO 512 `lineCache`를 우회해 **드래그 프레임마다** 재조판한다.
extension HwpSelectionGeometry {
    /// 위치의 캐럿 rect (페이지 로컬 top-down, 폭 0). 텍스트 단위를 못 찾거나
    /// 줄이 하나도 없으면 nil.
    public func caretRect(
        at position: HwpTextPosition,
        affinity: HwpCaretAffinity
    ) -> CGRect? {
        let units = units(forPage: position.pageIndex)
        guard let ordinal = units.firstIndex(where: {
            $0.blockIndex == position.blockIndex && $0.unitIndex == position.unitIndex
        }) else { return nil }
        let lines = drawnLines(pageIndex: position.pageIndex, unitOrdinal: ordinal)
        guard !lines.isEmpty else { return nil }
        let offset = min(
            max(position.characterOffset, 0),
            units[ordinal].attributedString.length
        )
        let line = Self.caretLine(in: lines, offset: offset, affinity: affinity)
        return Self.caretRect(in: line, offset: offset)
    }

    /// affinity로 줄을 고른다. 오프셋이 줄 경계면 후보가 둘(앞 줄의 끝, 뒷 줄의
    /// 시작)이고 문서 순서로 앞이 upstream, 뒤가 downstream이다. 어느 줄
    /// 범위에도 없는 오프셋(조판이 잘린 단위)은 가장 가까운 줄로 스냅한다.
    static func caretLine(
        in lines: [HwpDrawnLine],
        offset: Int,
        affinity: HwpCaretAffinity
    ) -> HwpDrawnLine {
        let containing = lines.filter {
            offset >= $0.stringRange.location
                && offset <= $0.stringRange.location + $0.stringRange.length
        }
        if let match = affinity == .downstream ? containing.last : containing.first {
            return match
        }
        return lines.min {
            lineDistance($0, offset: offset) < lineDistance($1, offset: offset)
        } ?? lines[0]
    }

    static func lineDistance(_ line: HwpDrawnLine, offset: Int) -> Int {
        let start = line.stringRange.location
        let end = start + line.stringRange.length
        if offset < start {
            return start - offset
        }
        if offset > end {
            return offset - end
        }
        return 0
    }

    /// 줄 안 오프셋의 캐럿 rect. x는 줄의 하이라이트 폭으로 클램프한다 —
    /// 줄바꿈으로 끊긴 줄은 후행 공백이 타이포그래픽 폭에 남아 있어
    /// (`selectionRect`는 그것을 뺀다) 클램프 없이는 끝 핸들만 하이라이트
    /// 오른쪽 끝 밖에 떠 있게 된다.
    static func caretRect(in line: HwpDrawnLine, offset: Int) -> CGRect {
        let lineRange = line.stringRange
        let clamped = min(
            max(offset, lineRange.location), lineRange.location + lineRange.length
        )
        let ctRange = CTLineGetStringRange(line.line)
        let localX = CTLineGetOffsetForStringIndex(
            line.line, clamped - lineRange.location + ctRange.location, nil
        )
        let selectionRect = line.selectionRect
        let x = min(
            max(line.baselineOrigin.x + localX, selectionRect.minX), selectionRect.maxX
        )
        return CGRect(
            x: x,
            y: line.baselineOrigin.y - line.ascent,
            width: 0,
            height: line.ascent + line.descent
        )
    }
}
