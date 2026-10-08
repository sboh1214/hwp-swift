import CoreGraphics
import CoreText
import Foundation
import HwpKitCore

// MARK: - 음영 배경·메모 앵커 괄호·줄 단위 채움 (#260)

extension HwpPageLayer {
    /// 음영 배경 (글리프보다 먼저) — run의 음영 상자를 줄의 색별 경로에 모은다 (`SolidFillBatch`).
    func collectShade(_ run: CTRun, lineOrigin: CGPoint, into shades: inout SolidFillBatch) {
        let attributes = runAttributes(run)
        guard let shade = attributes[HwpAttributedStringKey.shadeColor] else { return }
        let bounds = shadeBounds(of: run, attributes: attributes, lineOrigin: lineOrigin)
        shades.add(bounds, color: shade)
    }

    /// 음영 상자 — run의 진행 폭 × 1em. 실물 음영 상자는 정확히 1em이다 — run의 typographic
    /// ascent가 아니라 글리프에 밀착한 em 박스다 (라운드 7 실측: 상하 각 1px 여유).
    func shadeBounds(
        of run: CTRun, attributes: [NSAttributedString.Key: Any], lineOrigin: CGPoint
    ) -> CGRect {
        let typographic = runBounds(of: run, lineOrigin: lineOrigin)
        let size = runFont(attributes).map(CTFontGetSize) ?? typographic.height
        return CGRect(
            x: typographic.minX,
            y: lineOrigin.y - size * 0.15,
            width: typographic.width,
            height: size
        )
    }

    /// 메모 앵커의 둥근 녹색 괄호 쌍 (한글.app 실물 — memo 픽스처 앵커 괄호). 괄호는 앵커 범위의
    /// **양 끝**에만 선다 — 줄 안에서 잇닿은 앵커 run(글꼴·스크립트·자간이 갈라 놓은 조각)을 한
    /// 범위로 묶는다. run마다 세우면 자간이 있는 라틴 글자열(#260: 글자마다 run)의 글자마다 괄호가
    /// 섰다.
    func drawMemoAnchorBrackets(
        of runs: [CTRun], lineOrigin: CGPoint, clipMaxX: CGFloat?, in ctx: CGContext
    ) {
        var group: (bounds: CGRect, stroke: Any)?
        for run in runs {
            let attributes = runAttributes(run)
            guard let stroke = attributes[HwpAttributedStringKey.memoAnchorStroke],
                  attributes[HwpAttributedStringKey.shadeColor] != nil
            else {
                if let finished = group {
                    drawMemoAnchorBracket(finished.bounds, stroke: finished.stroke, in: ctx)
                    group = nil
                }
                continue
            }
            var bounds = shadeBounds(of: run, attributes: attributes, lineOrigin: lineOrigin)
            if let clipMaxX, bounds.maxX > clipMaxX {
                bounds.size.width = max(0, clipMaxX - bounds.minX)
            }
            if let current = group, abs(bounds.minX - current.bounds.maxX) < 0.5 {
                group = (current.bounds.union(bounds), current.stroke)
            } else {
                if let finished = group {
                    drawMemoAnchorBracket(finished.bounds, stroke: finished.stroke, in: ctx)
                }
                group = (bounds, stroke)
            }
        }
        if let finished = group {
            drawMemoAnchorBracket(finished.bounds, stroke: finished.stroke, in: ctx)
        }
    }

    /// 범위 양 끝의 둥근 괄호 쌍 — 여는 쪽은 옅고 닫는 쪽이 진하다 (라운드 10 실측).
    private func drawMemoAnchorBracket(_ bounds: CGRect, stroke: Any, in ctx: CGContext) {
        func bracket(atX x: CGFloat, cornerX: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let radius: CGFloat = 1.2
            path.move(to: CGPoint(x: cornerX, y: bounds.minY))
            path.addArc(
                tangent1End: CGPoint(x: x, y: bounds.minY),
                tangent2End: CGPoint(x: x, y: bounds.minY + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: x, y: bounds.maxY - radius))
            path.addArc(
                tangent1End: CGPoint(x: x, y: bounds.maxY),
                tangent2End: CGPoint(x: cornerX, y: bounds.maxY),
                radius: radius
            )
            return path
        }
        let strokeColor = stroke as! CGColor // swiftlint:disable:this force_cast
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(strokeColor)
        ctx.addPath(bracket(atX: bounds.maxX, cornerX: bounds.maxX - 1.2))
        ctx.setLineWidth(0.9)
        ctx.strokePath()
        ctx.addPath(bracket(atX: bounds.minX, cornerX: bounds.minX + 1.2))
        ctx.setLineWidth(0.55)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// 줄 하나의 음영·실선 장식을 색별 **한 경로**로 모아 칠한다 — run마다 따로 칠하면 소수 좌표에서
/// 맞닿은 사각형의 경계 픽셀이 두 번 반씩 덮여 옅은 이음매가 남는다(같은 색 사각형 [2, 10.5]·
/// [10.5, 19.8]의 경계 열이 0.75 커버리지 — 실측). 한 경로로 채우면 커버리지를 합집합 위에서 재므로
/// 이음매가 없다. 색은 처음 나온 순서대로 칠한다.
struct SolidFillBatch {
    private var groups: [(color: CGColor, path: CGMutablePath)] = []
    /// 이 x 오른쪽은 칠하지 않는다 — 줄 끝 글자에 매달린 양수 자간 (`lineEndTrackingClip`).
    let clipMaxX: CGFloat?

    init(clipMaxX: CGFloat? = nil) {
        self.clipMaxX = clipMaxX
    }

    /// `color`(nil이면 검정)의 경로에 사각형을 더한다.
    mutating func add(_ rect: CGRect, color: Any?) {
        var rect = rect
        if let clipMaxX, rect.maxX > clipMaxX {
            guard clipMaxX > rect.minX else { return }
            rect.size.width = clipMaxX - rect.minX
        }
        let resolved: CGColor = if let color, CFGetTypeID(color as CFTypeRef) == CGColor.typeID {
            unsafeBitCast(color as CFTypeRef, to: CGColor.self)
        } else {
            CGColor(gray: 0, alpha: 1)
        }
        if let index = groups.firstIndex(where: { $0.color == resolved }) {
            groups[index].path.addRect(rect)
        } else {
            let path = CGMutablePath()
            path.addRect(rect)
            groups.append((resolved, path))
        }
    }

    func fill(in ctx: CGContext) {
        for group in groups {
            ctx.setFillColor(group.color)
            ctx.addPath(group.path)
            ctx.fillPath()
        }
    }
}
