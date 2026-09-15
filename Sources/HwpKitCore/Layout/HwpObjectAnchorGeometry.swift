import CoreGraphics
import CoreHwp
import Foundation

/// 개체 앵커 좌표 산식의 **단일 소유자** (#73).
///
/// 같은 산식을 두 경로가 쓴다 — 페이지 흐름 경로(`HwpPaginator`)와 컨테이너 안
/// 수집 경로(`HwpParagraphObjectCollector`). 종전에는 두 곳이 각자 구현을 들고
/// "같은 산식이다"라고 주석으로만 묶여 있어, 한쪽만 고치면 조용히 갈라졌다.
/// #80이 측정·렌더 줄바꿈에 대해 `HwpLineBreaker`로 한 것과 같은 처리다.
///
/// **여기 들어오는 것은 두 경로가 실제로 공유하는 산식뿐이다.** 컨테이너 경로의
/// `origin(commonProperty:size:placement:cursorX:)`은 페이지 경로의
/// `anchoredObjectFrame`을 문단 rect로 **근사**한 것이라 같은 함수가 아니다 —
/// 옮기지 말 것. 공유하는 것은 그 근사가 안에서 부르는 `aligned`뿐이다.
enum HwpObjectAnchorGeometry {
    /// 앵커 규칙(표 70)의 기준 좌표(base) + 여유 폭(extent) + 개체 치수(size)와
    /// 정렬로 배치 좌표를 낸다.
    ///
    /// `extent`가 0이면 정렬이 무효다 — 페이지 경로에서 세로 기준이 '문단'일 때
    /// extent를 0으로 넘겨 정렬을 끄는 것이 이 규칙에 기댄다.
    static func aligned(
        base: CGFloat,
        extent: CGFloat,
        size: CGFloat,
        alignment: CoreHwp.HwpCommonCtrlRelativeAlignment?
    ) -> CGFloat {
        guard extent > 0 else { return base }
        return switch alignment {
        case .center: base + (extent - size) / 2
        case .bottomOrRight, .outside: base + extent - size
        case .topOrLeft, .inside, nil: base
        }
    }

    /// 글자처럼 취급되는 개체의 줄 앵커 좌표 — 문단 rect 원점 기준.
    ///
    /// 세로는 줄 상자 모델(#178·#180)을 따른다: `lineOrigin.y`는 그 줄 **상자 상단**(문단
    /// 첫 줄 상자 상단 기준)이고 `lineBaseline`은 상자 상단에서 베이스라인 앵커까지의 거리
    /// (`HwpDrawnTextLayout.baselineAnchor`)다. 개체 바닥은 베이스라인에 놓되 개체가
    /// 베이스라인 위 공간보다 크면 상자 상단에 붙는다 — 개체가 상자를 정한 줄(코퍼스의
    /// 전부)은 상자 높이 = 개체 높이라 개체 상단 = 상자 상단이고, 렌더가 그 줄 글자를 그리는
    /// 자리(상자 상단 + 0.85 × 개체 높이)와 같은 기준이다. 두 경로가 이 식을 공유한다.
    /// 상자보다 작은 개체의 세로 자리는 한글 실측 전이다 (#195).
    static func inlineAnchorOrigin(
        paragraphOrigin: CGPoint,
        lineBaseline: CGFloat,
        lineOrigin: CGPoint,
        xOffset: CGFloat,
        ascent: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: paragraphOrigin.x + lineOrigin.x + xOffset,
            y: paragraphOrigin.y + lineOrigin.y + max(0, lineBaseline - ascent)
        )
    }
}
