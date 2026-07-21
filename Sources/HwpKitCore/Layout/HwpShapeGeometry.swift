@preconcurrency import CoreGraphics
import CoreHwp
import Foundation

/// HWP 개체 요소(SHAPE_COMPONENT)를 `CGPath`와 fill/stroke 속성으로 변환한다.
///
/// 선/사각형/타원/호/다각형/곡선의 세부 레코드 좌표를 개체 좌표계에서 읽어
/// 렌더링 행렬(표 84)을 적용한 뒤 point 단위 블록-로컬 좌표로 변환한다.
/// 세부 레코드가 없으면 개체 크기의 bounding box로 대체한다.
public struct HwpShapeGeometry: @unchecked Sendable {
    public let path: CGPath
    public let fillColor: CGColor?
    public let strokeColor: CGColor?
    public let strokeWidth: CGFloat

    public init(path: CGPath, fillColor: CGColor?, strokeColor: CGColor?, strokeWidth: CGFloat) {
        self.path = path
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    /// 개체 요소에서 geometry를 빌드한다.
    ///
    /// - Parameters:
    ///   - component: 좌표를 읽을 SHAPE_COMPONENT
    ///   - size: 블록 크기 (pt). 세부 레코드가 없을 때 bounding box로 쓴다.
    /// - Returns: 변환된 geometry. 지원하는 세부 레코드도 크기도 없으면 nil.
    public static func build(
        component: CoreHwp.HwpShapeComponent,
        size: CGSize
    ) -> HwpShapeGeometry? {
        let detail = component.detail
        let transform = renderTransform(from: detail)
        let path = shapePath(component: component, size: size, transform: transform)
        guard let path else { return nil }

        var fill: CGColor?
        if let fillInfo = detail?.fill, fillInfo.hasSolidFill,
           let background = fillInfo.solidBackgroundColor
        {
            fill = background.cgColor
        }
        var stroke: CGColor? = CGColor.hwpBlack
        var strokeWidth: CGFloat = 1
        if let borderLine = detail?.borderLine {
            if borderLine.hasVisibleLine {
                stroke = borderLine.color.cgColor
                let width = HwpUnits.points(fromHwpUnit: borderLine.width)
                strokeWidth = width > 0 ? width : 1
            } else {
                stroke = nil
                strokeWidth = 0
            }
        }
        return HwpShapeGeometry(
            path: path,
            fillColor: fill,
            strokeColor: stroke,
            strokeWidth: strokeWidth
        )
    }

    // MARK: - Public path helpers (testability)

    /// CGRect에서 사각형 CGPath를 생성한다.
    public static func rectanglePath(from rect: CGRect) -> CGPath {
        CGPath(rect: rect, transform: nil)
    }

    /// CGRect에서 타원 CGPath를 생성한다.
    public static func ellipsePath(from rect: CGRect) -> CGPath {
        CGPath(ellipseIn: rect, transform: nil)
    }

    /// 두 점을 잇는 직선 CGPath를 생성한다.
    public static func linePath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    /// 점 배열에서 닫힌 다각형 CGPath를 생성한다. 점이 2개 미만이면 nil을 반환한다.
    public static func polygonPath(from points: [CGPoint]) -> CGPath? {
        guard points.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    /// 호로 바뀐 타원(표 96 property bit1): 두 축으로 타원 반지름을, 호 시작/끝점
    /// (offset 28/36)으로 각도를 잡아 부분 타원 호를 그린다 — 완전 타원 대신 실제
    /// 호 구간만 (R45 #2). 축을 각도로도 쓰는 arcPath(표 101)와 달리 타원은
    /// 반지름과 호 끝점이 별도 필드다.
    public static func ellipseArcPath(
        of ellipse: CoreHwp.HwpShapeEllipseDetail,
        start: CoreHwp.HwpShapePoint,
        end: CoreHwp.HwpShapePoint,
        transform: CGAffineTransform
    ) -> CGPath {
        let cx = CGFloat(ellipse.center.x)
        let cy = CGFloat(ellipse.center.y)
        let rx = max(max(abs(CGFloat(ellipse.firstAxis.x) - cx), abs(CGFloat(ellipse.secondAxis.x) - cx)), 0.5)
        let ry = max(max(abs(CGFloat(ellipse.firstAxis.y) - cy), abs(CGFloat(ellipse.secondAxis.y) - cy)), 0.5)
        func angle(_ pt: CoreHwp.HwpShapePoint) -> CGFloat {
            atan2((CGFloat(pt.y) - cy) / ry, (CGFloat(pt.x) - cx) / rx)
        }
        let toWorld = CGAffineTransform(scaleX: rx, y: ry)
            .concatenating(CGAffineTransform(translationX: cx, y: cy))
            .concatenating(transform)
        let path = CGMutablePath()
        path.addArc(
            center: .zero, radius: 1,
            startAngle: angle(start), endAngle: angle(end),
            clockwise: false, transform: toWorld
        )
        return path
    }
}

extension HwpShapeGeometry: Hashable {
    public static func == (lhs: HwpShapeGeometry, rhs: HwpShapeGeometry) -> Bool {
        lhs.path == rhs.path
            && lhs.strokeWidth == rhs.strokeWidth
            && colorComponentsEqual(lhs.fillColor, rhs.fillColor)
            && colorComponentsEqual(lhs.strokeColor, rhs.strokeColor)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path.boundingBox.origin.x)
        hasher.combine(path.boundingBox.origin.y)
        hasher.combine(path.boundingBox.size.width)
        hasher.combine(path.boundingBox.size.height)
        hasher.combine(strokeWidth)
        fillColor?.components?.forEach { hasher.combine($0) }
        strokeColor?.components?.forEach { hasher.combine($0) }
    }

    private static func colorComponentsEqual(_ lhs: CGColor?, _ rhs: CGColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.components == right.components
        default: false
        }
    }
}

private extension HwpShapeGeometry {
    /// 렌더링 행렬 (표 84): translation 행렬에 scale/rotation 쌍을 차례로 합성한다.
    /// 좌표 적용 후 HWPUNIT → pt 축소를 함께 수행한다.
    static func renderTransform(from detail: HwpShapeComponentDetail?) -> CGAffineTransform {
        let hwpUnitToPoint = CGAffineTransform(scaleX: 0.01, y: 0.01)
        guard let detail, detail.translationMatrix.count == 6 else {
            return hwpUnitToPoint
        }

        var combined = affineTransform(detail.translationMatrix)
        for pair in detail.scaleRotationMatrixPairs {
            guard pair.scale.count == 6, pair.rotation.count == 6 else { continue }
            combined = affineTransform(pair.scale)
                .concatenating(affineTransform(pair.rotation))
                .concatenating(combined)
        }
        return combined.concatenating(hwpUnitToPoint)
    }

    /// double[6] = [m0 m1 m2; m3 m4 m5] (x' = m0·x + m1·y + m2)를 CGAffineTransform으로 변환.
    static func affineTransform(_ matrix: [Double]) -> CGAffineTransform {
        CGAffineTransform(
            a: matrix[0],
            b: matrix[3],
            c: matrix[1],
            d: matrix[4],
            tx: matrix[2],
            ty: matrix[5]
        )
    }

    static func shapePath(
        component: CoreHwp.HwpShapeComponent,
        size: CGSize,
        transform: CGAffineTransform
    ) -> CGPath? {
        if let line = component.lineArray.first?.lineDetail {
            return linePath(
                from: point(line.start, transform),
                to: point(line.end, transform)
            )
        }
        if let rectangle = component.rectangleArray.first?.rectangleDetail {
            // 모서리 곡률이 있으면 둥근 사각형 path, 아니면 기존 polygon (곡률 0은
            // 렌더 불변, #7).
            if rectangle.cornerRoundness > 0,
               let rounded = roundedRectanglePath(rectangle, transform: transform)
            {
                return rounded
            }
            return polygonPath(from: rectangle.corners.map { point($0, transform) })
        }
        if let polygon = component.polygonArray.first?.polygonDetail {
            return polygonPath(from: polygon.points.map { point($0, transform) })
        }
        if let curve = component.curveArray.first?.curveDetail {
            return curvePath(curve, transform: transform)
        }
        if let ellipse = component.ellipseArray.first?.ellipseDetail {
            // 호로 바뀐 타원(property bit1)은 완전 타원 대신 호 시작/끝점으로 부분
            // 호를 그린다 (R45 #2). 끝점이 없는 짧은 레코드는 완전 타원 폴백.
            if ellipse.isArc, let start = ellipse.arcStart, let end = ellipse.arcEnd {
                return ellipseArcPath(of: ellipse, start: start, end: end, transform: transform)
            }
            // 로컬 타원 path에 렌더 행렬을 적용한다 — 회전/전단 타원을 축 정렬
            // bounding rect로 뭉개던 것 대신 정확한 affine (#5). 회전 없는 순수
            // scale에서는 기존 결과와 동일하다.
            return ellipsePath(of: ellipse, transform: transform)
        }
        if let arc = component.arcArray.first?.arcDetail {
            return arcPath(of: arc, transform: transform)
        }
        guard size.width > 0 || size.height > 0 else { return nil }
        return rectanglePath(
            from: CGRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
        )
    }

    static func curvePath(_ curve: HwpShapeCurveDetail, transform: CGAffineTransform) -> CGPath? {
        let points = curve.points.map { point($0, transform) }
        guard points.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.move(to: points[0])
        var index = 1
        while index < points.count {
            let segmentType = index - 1 < curve.segmentTypes.count
                ? curve.segmentTypes[index - 1]
                : 0
            if segmentType == 1, index + 1 < points.count {
                // 곡선 구간: 이웃 두 점을 제어점/종점으로 하는 quad curve 근사
                path.addQuadCurve(to: points[index + 1], control: points[index])
                index += 2
            } else {
                path.addLine(to: points[index])
                index += 1
            }
        }
        return path
    }

    /// 로컬(변환 전) 타원 path를 만들어 렌더 행렬을 path에 적용한다 (#5).
    /// 반지름은 중심~두 축 끝점 거리로 잡는다 (기존 boundingRect와 동일 규칙).
    /// 순수 scale 변환에서는 축 정렬 bounding rect 결과와 값이 같고, 회전/전단이
    /// 있으면 path 변환이 정확한 affine 타원을 만든다.
    static func ellipsePath(
        of ellipse: HwpShapeEllipseDetail,
        transform: CGAffineTransform
    ) -> CGPath {
        let cx = CGFloat(ellipse.center.x)
        let cy = CGFloat(ellipse.center.y)
        let radiusX = max(
            abs(CGFloat(ellipse.firstAxis.x) - cx),
            abs(CGFloat(ellipse.secondAxis.x) - cx)
        )
        let radiusY = max(
            abs(CGFloat(ellipse.firstAxis.y) - cy),
            abs(CGFloat(ellipse.secondAxis.y) - cy)
        )
        let localRect = CGRect(
            x: cx - radiusX, y: cy - radiusY,
            width: max(radiusX * 2, 1), height: max(radiusY * 2, 1)
        )
        var matrix = transform
        return CGPath(ellipseIn: localRect, transform: &matrix)
    }

    /// 호(표 101): 두 축 점을 호의 시작/끝으로 보고 부분 타원 호 경로를 만든다 —
    /// 완전 타원 대신 실제 호 구간만 그린다 (#4). 호 종류(pie/chord)는 열린 호로
    /// 근사하고, 회전/전단은 렌더 행렬로 반영한다.
    static func arcPath(of arc: HwpShapeArcDetail, transform: CGAffineTransform) -> CGPath {
        let cx = CGFloat(arc.center.x)
        let cy = CGFloat(arc.center.y)
        let rx = max(max(abs(CGFloat(arc.firstAxis.x) - cx), abs(CGFloat(arc.secondAxis.x) - cx)), 0.5)
        let ry = max(max(abs(CGFloat(arc.firstAxis.y) - cy), abs(CGFloat(arc.secondAxis.y) - cy)), 0.5)
        func angle(_ pt: HwpShapePoint) -> CGFloat {
            atan2((CGFloat(pt.y) - cy) / ry, (CGFloat(pt.x) - cx) / rx)
        }
        // 단위원 호 → 타원 스케일 → 중심 이동 → 렌더 행렬
        let toWorld = CGAffineTransform(scaleX: rx, y: ry)
            .concatenating(CGAffineTransform(translationX: cx, y: cy))
            .concatenating(transform)
        let path = CGMutablePath()
        path.addArc(
            center: .zero, radius: 1,
            startAngle: angle(arc.firstAxis), endAngle: angle(arc.secondAxis),
            clockwise: false, transform: toWorld
        )
        return path
    }

    /// 모서리 곡률(표 94: 0 직각/20 둥근/50 반원)을 반영한 둥근 사각형 path (#7).
    /// 로컬 rect + corner radius로 만들어 렌더 행렬을 path에 적용한다.
    /// 50% = 짧은 변이 반원 → radius = 곡률/100 × 짧은 변 (짧은 변/2로 상한).
    static func roundedRectanglePath(
        _ rectangle: HwpShapeRectangleDetail,
        transform: CGAffineTransform
    ) -> CGPath? {
        let xs = rectangle.corners.map { CGFloat($0.x) }
        let ys = rectangle.corners.map { CGFloat($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY
        else { return nil }
        let localRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let shorter = min(localRect.width, localRect.height)
        let radius = min(CGFloat(rectangle.cornerRoundness) / 100 * shorter, shorter / 2)
        var matrix = transform
        return CGPath(
            roundedRect: localRect,
            cornerWidth: radius, cornerHeight: radius, transform: &matrix
        )
    }

    static func point(_ shapePoint: HwpShapePoint, _ transform: CGAffineTransform) -> CGPoint {
        CGPoint(x: CGFloat(shapePoint.x), y: CGFloat(shapePoint.y)).applying(transform)
    }
}
