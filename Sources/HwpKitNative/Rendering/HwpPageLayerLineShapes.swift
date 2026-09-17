import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
import QuartzCore

// MARK: - 글자선의 선 모양 (#191) — 점선·파선·원형 점선·여러 줄·물결

extension HwpPageLayer {
    /// 장식선 하나의 모양 입력 — `fillLine`이 실선이 아닐 때 `fillShapedLine`에 넘긴다.
    struct ShapedLine {
        /// 표 25 선 종류 (조판 키 없으면 `.line`)
        let shape: HwpBorderType
        /// 여러 줄·물결 띠의 자리 (아래 밑줄·취소선·위 밑줄)
        let placement: HwpLineShapeGeometry.Placement
        /// 첨자 축소 전 글자 크기 — 패턴·띠·물결의 축척
        let fontSize: CGFloat
        /// 글자 모양 run의 가로 범위 (`lineShapeSpans`, 묶음의 첫 run만 값이 있다)
        let span: CGRect?
    }

    /// 조판이 실은 선 모양 키 (`HwpBorderType.rawValue`) — 없거나 모르는 값이면 실선
    func lineShape(_ value: Any?) -> HwpBorderType {
        guard let raw = (value as? NSNumber)?.intValue else { return .line }
        return HwpBorderType(rawValue: raw) ?? .line
    }

    /// 선 모양(점선·파선·원형 점선·여러 줄·물결, #191)을 펼 **글자 모양 run**의 가로 범위 —
    /// 같은 글자 모양 id(`charShapeId`)의 잇닿은 CoreText run을 한 묶음으로 보고 묶음의
    /// 첫 run 자리에 합친 경계를, 나머지 자리에 nil을 둔다. 한글은 패턴을 글자 모양 run마다
    /// 새로 시작하고 그 안의 스크립트 슬롯 전환(한글↔라틴, CoreText가 run을 가르는 경계)은
    /// 이어 그린다 (2026-09-17 실측: "가나다 abc 라마" 한 글자 모양의 긴 점선이 한 위상으로
    /// 이어지고, 색만 다른 이웃 글자 모양 "ab"·"cd efgh"·" ij"는 각각 다시 시작). 묶는
    /// 열쇠가 글자 모양 id인 이유는 `msWordStrikethroughFonts`와 같다 — 속성 사전 비교는
    /// 양쪽 정렬 자간·문단 끝 상자가 한 글자 모양을 가른다. id 없는 폴백 run은 홀로 선다.
    /// 실선은 이 묶음을 쓰지 않고 run마다 그린다 (이어 붙인 사각형과 같은 결과).
    func lineShapeSpans(of runs: [CTRun], lineOrigin: CGPoint) -> [CGRect?] {
        var spans: [CGRect?] = Array(repeating: nil, count: runs.count)
        var groupStart = 0
        var groupShape: NSNumber?
        for (index, run) in runs.enumerated() {
            let bounds = runBounds(of: run, lineOrigin: lineOrigin)
            let shape = runAttributes(run)[HwpAttributedStringKey.charShapeId] as? NSNumber
            if index > 0, let shape, let groupShape, shape == groupShape,
               let union = spans[groupStart]
            {
                spans[groupStart] = union.union(bounds)
            } else {
                groupStart = index
                groupShape = shape
                spans[index] = bounds
            }
        }
        return spans
    }

    /// 실선이 아닌 장식선 — 글자 모양 run의 폭 `span`(묶음의 첫 run만 받는다,
    /// `lineShapeSpans`; 나머지 run은 아무것도 그리지 않는다)에 `HwpLineShapeGeometry`의
    /// 경로를 편다. 패턴·띠·물결의 축척은 첨자 축소 전 글자 크기이고, 로컬 y(양수 = 아래)를
    /// 텍스트 공간(y-위)으로 뒤집어 단선 중심(`lineOrigin.y + line.center`)에 놓는다.
    func fillShapedLine(
        line: HwpDecorationLineGeometry.Line,
        lineOrigin: CGPoint,
        shaped: ShapedLine,
        in ctx: CGContext
    ) {
        guard let span = shaped.span,
              let path = HwpLineShapeGeometry.path(for: HwpLineShapeGeometry.Line(
                  shape: shaped.shape, length: span.width, thickness: line.thickness,
                  scale: .characterLine(fontSize: shaped.fontSize), placement: shaped.placement
              ))
        else { return }
        // 로컬 (x, y) → 텍스트 공간 (span.minX + x, 선 중심 − y)
        var transform = CGAffineTransform(
            a: 1, b: 0, c: 0, d: -1, tx: span.minX, ty: lineOrigin.y + line.center
        )
        guard let placed = path.copy(using: &transform) else { return }
        ctx.addPath(placed)
        ctx.fillPath()
    }
}
