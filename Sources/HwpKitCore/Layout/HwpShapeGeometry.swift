@preconcurrency import CoreGraphics
@preconcurrency import CoreHwp
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
            return polygonPath(from: rectangle.corners.map { point($0, transform) })
        }
        if let polygon = component.polygonArray.first?.polygonDetail {
            return polygonPath(from: polygon.points.map { point($0, transform) })
        }
        if let curve = component.curveArray.first?.curveDetail {
            return curvePath(curve, transform: transform)
        }
        if let ellipse = component.ellipseArray.first?.ellipseDetail {
            return ellipsePath(from: boundingRect(of: ellipse, transform: transform))
        }
        if let arc = component.arcArray.first?.arcDetail {
            return ellipsePath(from: boundingRect(of: arc, transform: transform))
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

    /// 타원/호의 중심 + 두 축 끝점에서 bounding rect를 계산한다.
    static func boundingRect(
        of ellipse: HwpShapeEllipseDetail,
        transform: CGAffineTransform
    ) -> CGRect {
        let center = point(ellipse.center, transform)
        let axis1 = point(ellipse.firstAxis, transform)
        let axis2 = point(ellipse.secondAxis, transform)
        let radiusX = max(abs(axis1.x - center.x), abs(axis2.x - center.x))
        let radiusY = max(abs(axis1.y - center.y), abs(axis2.y - center.y))
        return CGRect(
            x: center.x - radiusX,
            y: center.y - radiusY,
            width: max(radiusX * 2, 1),
            height: max(radiusY * 2, 1)
        )
    }

    static func point(_ shapePoint: HwpShapePoint, _ transform: CGAffineTransform) -> CGPoint {
        CGPoint(x: CGFloat(shapePoint.x), y: CGFloat(shapePoint.y)).applying(transform)
    }
}
