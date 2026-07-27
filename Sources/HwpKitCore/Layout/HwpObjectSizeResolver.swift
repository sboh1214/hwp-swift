import CoreGraphics
import CoreHwp
import Foundation

/// 개체 저장 크기 (표 70 width/height)의 기준 해석기. 크기 기준이 절대값이
/// 아니면 (종이/쪽/단/문단) 저장값은 HWPUNIT 길이가 아니라 기준 프레임에
/// 대한 퍼센트다 (10000 = 100%) — 무조건 HWPUNIT 변환하면 100% 폭 개체가
/// 100pt로 줄어든다. paginator가 현재 페이지/단 기하로 만들어 전용 레이아웃
/// 경로 (표 폭·글상자·셀 그림·줄 공간 예약)에 전달한다.
public struct HwpObjectSizeResolver: Sendable {
    /// 용지 크기 (pt) — 기준 '종이'
    let paperSize: CGSize
    /// 본문 콘텐츠 프레임 크기 (pt) — 기준 '쪽'
    let contentSize: CGSize
    /// 현재 단 폭 (pt) — 기준 '단'
    let columnWidth: CGFloat
    /// 현재 문단 폭 (pt) — 기준 '문단'. 본문은 단 폭 − 문단 좌우 여백,
    /// 셀/글상자 안에서는 컨테이너 안폭 (#2). 미지정이면 단 폭.
    let paragraphWidth: CGFloat

    public init(
        paperSize: CGSize,
        contentSize: CGSize,
        columnWidth: CGFloat,
        paragraphWidth: CGFloat? = nil
    ) {
        self.paperSize = paperSize
        self.contentSize = contentSize
        self.columnWidth = columnWidth
        self.paragraphWidth = paragraphWidth ?? columnWidth
    }

    /// 문단 폭만 바꾼 사본 — 셀/글상자 레이아웃이 컨테이너 안폭으로 좁혀
    /// 하위 문단에 전달한다.
    public func withParagraphWidth(_ width: CGFloat) -> HwpObjectSizeResolver {
        HwpObjectSizeResolver(
            paperSize: paperSize,
            contentSize: contentSize,
            columnWidth: columnWidth,
            paragraphWidth: max(1, width)
        )
    }

    /// 개체 폭 저장값을 기준에 따라 pt로 해석한다.
    public func width(
        _ raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectWidthRelativeTo?
    ) -> CGFloat {
        switch basis {
        case .paper: CGFloat(raw) / 10000 * paperSize.width
        case .page: CGFloat(raw) / 10000 * contentSize.width
        case .column: CGFloat(raw) / 10000 * columnWidth
        case .paragraph: CGFloat(raw) / 10000 * paragraphWidth
        case .absolute, nil: HwpUnits.points(fromHwpUnitU: raw)
        }
    }

    /// 개체 높이 저장값을 기준에 따라 pt로 해석한다.
    public func height(
        _ raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectHeightRelativeTo?
    ) -> CGFloat {
        switch basis {
        case .paper: CGFloat(raw) / 10000 * paperSize.height
        case .page: CGFloat(raw) / 10000 * contentSize.height
        case .absolute, nil: HwpUnits.points(fromHwpUnitU: raw)
        }
    }

    /// commonProperty의 저장 크기를 해석한다 (선택적 resolver 공용 헬퍼 —
    /// resolver가 없으면 절대값 (HWPUNIT) 변환으로 폴백).
    public static func width(
        _ raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectWidthRelativeTo?,
        resolver: HwpObjectSizeResolver?
    ) -> CGFloat {
        resolver?.width(raw, basis: basis) ?? HwpUnits.points(fromHwpUnitU: raw)
    }

    public static func height(
        _ raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectHeightRelativeTo?,
        resolver: HwpObjectSizeResolver?
    ) -> CGFloat {
        resolver?.height(raw, basis: basis) ?? HwpUnits.points(fromHwpUnitU: raw)
    }

    /// commonProperty의 저장 폭/높이를 각 기준으로 해석한다 (0 이하 성분은
    /// 그대로 반환 — 개체 요소 detail 폴백은 호출부 몫).
    public static func size(
        of property: CoreHwp.HwpCommonCtrlProperty,
        resolver: HwpObjectSizeResolver?
    ) -> CGSize {
        let info = property.propertyInfo
        return CGSize(
            width: width(property.width, basis: info.widthRelativeTo, resolver: resolver),
            height: height(property.height, basis: info.heightRelativeTo, resolver: resolver)
        )
    }
}
