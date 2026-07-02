import CoreGraphics
import Foundation

/// 한글 문서의 단위 변환 유틸리티.
///
/// HWP 문서는 1/7200인치를 기본 단위(HWPUNIT)로 사용한다.
/// 이 enum은 HWPUNIT, 포인트(pt), 픽셀(px) 간의 변환을 제공한다.
///
/// - 1 inch = 7200 HWPUNIT
/// - 1 inch = 72 pt
/// - 따라서 1 pt = 100 HWPUNIT
public enum HwpUnits {
    /// HWPUNIT을 포인트로 변환한다.
    ///
    /// 1 pt = 100 HWPUNIT이므로, HWPUNIT을 100으로 나누어 포인트를 얻는다.
    ///
    /// - Parameter hwpUnit: 변환할 HWPUNIT 값 (Int32)
    /// - Returns: 포인트 단위의 CGFloat 값
    public static func points(fromHwpUnit hwpUnit: Int32) -> CGFloat {
        CGFloat(hwpUnit) / 100
    }

    /// 부호 없는 HWPUNIT을 포인트로 변환한다.
    ///
    /// 1 pt = 100 HWPUNIT이므로, HWPUNIT을 100으로 나누어 포인트를 얻는다.
    ///
    /// - Parameter hwpUnit: 변환할 HWPUNIT 값 (UInt32)
    /// - Returns: 포인트 단위의 CGFloat 값
    public static func points(fromHwpUnitU hwpUnit: UInt32) -> CGFloat {
        CGFloat(hwpUnit) / 100
    }

    /// 16비트 HWPUNIT을 포인트로 변환한다.
    ///
    /// 1 pt = 100 HWPUNIT이므로, HWPUNIT을 100으로 나누어 포인트를 얻는다.
    ///
    /// - Parameter hwpUnit: 변환할 HWPUNIT 값 (Int16)
    /// - Returns: 포인트 단위의 CGFloat 값
    public static func points(fromHwpUnit16 hwpUnit: Int16) -> CGFloat {
        CGFloat(hwpUnit) / 100
    }

    /// HWPUNIT을 픽셀로 변환한다.
    ///
    /// 1 inch = 7200 HWPUNIT이고, 1 inch = dpi 픽셀이므로,
    /// HWPUNIT을 픽셀로 변환하려면 dpi / 7200을 곱한다.
    ///
    /// - Parameters:
    ///   - hwpUnit: 변환할 HWPUNIT 값
    ///   - dpi: 화면의 DPI (기본값: 96)
    /// - Returns: 픽셀 단위의 CGFloat 값
    public static func pixels(fromHwpUnit hwpUnit: Int32, dpi: CGFloat = 96) -> CGFloat {
        CGFloat(hwpUnit) * dpi / 7200
    }

    /// 포인트를 HWPUNIT으로 변환한다.
    ///
    /// 1 pt = 100 HWPUNIT이므로, 포인트에 100을 곱하고 반올림하여 HWPUNIT을 얻는다.
    ///
    /// - Parameter points: 변환할 포인트 값
    /// - Returns: HWPUNIT 단위의 Int32 값
    public static func hwpUnit(fromPoints points: CGFloat) -> Int32 {
        Int32((points * 100).rounded())
    }

    /// 너비와 높이를 HWPUNIT에서 포인트 기반 CGSize로 변환한다.
    ///
    /// 각 차원을 100으로 나누어 포인트 단위로 변환한다.
    ///
    /// - Parameters:
    ///   - width: 너비 (HWPUNIT, UInt32)
    ///   - height: 높이 (HWPUNIT, UInt32)
    /// - Returns: 포인트 단위의 CGSize
    public static func size(fromHwpUnitWidth width: UInt32, height: UInt32) -> CGSize {
        CGSize(
            width: CGFloat(width) / 100,
            height: CGFloat(height) / 100
        )
    }
}
