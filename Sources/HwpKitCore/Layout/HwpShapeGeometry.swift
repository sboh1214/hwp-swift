@preconcurrency import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

/// HWP shape control payload을 `CGPath`와 fill/stroke 속성으로 변환한다.
///
/// v1에서 geometry가 완전히 디코딩된 shape는 `rectangle`과 `ellipse`뿐이다.
/// 나머지 종류(line, arc, polygon, curve)의 shape component detail은
/// raw payload로만 존재하므로 `build(from:index:)`가 nil을 반환한다.
public struct HwpShapeGeometry: Sendable {
    public let path: CGPath
    public let fillColor: CGColor?
    public let strokeColor: CGColor?
    public let strokeWidth: CGFloat

    /// CoreHwp shape control에서 geometry를 빌드한다.
    ///
    /// - Parameters:
    ///   - ctrl: 변환할 `HwpCtrlId`
    ///   - index: `HwpIndex` (v1에서는 미사용; 향후 border/fill color 해석 예정)
    /// - Returns: 변환된 geometry, 또는 지원하지 않는 shape 종류이면 nil
    public static func build(from ctrl: CoreHwp.HwpCtrlId, index _: HwpIndex) -> HwpShapeGeometry? {
        switch ctrl {
        case let .rectangle(sc):
            guard let prop = sc.commonCtrlProperty else { return nil }
            return HwpShapeGeometry(
                path: rectanglePath(from: boundingRect(from: prop)),
                fillColor: nil,
                strokeColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                strokeWidth: 1.0
            )
        case let .ellipse(sc):
            guard let prop = sc.commonCtrlProperty else { return nil }
            return HwpShapeGeometry(
                path: ellipsePath(from: boundingRect(from: prop)),
                fillColor: nil,
                strokeColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                strokeWidth: 1.0
            )
        default:
            // line/arc/polygon/curve/picture/ole/container/shape: component detail은 raw-only
            return nil
        }
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

private extension HwpShapeGeometry {
    static func boundingRect(from prop: CoreHwp.HwpCommonCtrlProperty) -> CGRect {
        CGRect(
            x: HwpUnits.points(fromHwpUnitU: prop.horizontalOffset),
            y: HwpUnits.points(fromHwpUnitU: prop.verticalOffset),
            width: HwpUnits.points(fromHwpUnitU: prop.width),
            height: HwpUnits.points(fromHwpUnitU: prop.height)
        )
    }
}
