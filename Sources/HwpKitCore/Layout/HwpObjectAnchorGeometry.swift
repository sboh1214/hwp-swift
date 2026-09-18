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
    ///
    /// 결과는 줄이 예약한 **바깥 상자**(개체 + 바깥 여백, `OuterMargins`)의 원점이다 —
    /// 개체 자신의 원점은 `inlineObjectOrigin`이 여백만큼 들여 낸다.
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

    /// 개체의 바깥 여백 (표 70 `marginArray` — 왼쪽·오른쪽·위쪽·아래쪽, pt).
    ///
    /// 글자처럼 취급 개체는 줄에서 **바깥 상자** = (폭 + 왼쪽 + 오른쪽) × (높이 + 위쪽 +
    /// 아래쪽)을 한 글자로 차지하고, 개체는 그 안에서 (왼쪽, 위쪽)만큼 들어가 놓인다
    /// (#193, 한컴오피스 한글 12.30 macOS 실측 2026-09-18: 30pt 표에 바깥 여백 왼 10·오 5·
    /// 위 7·아래 3pt를 주면 줄 캐시 `vertsize`가 40pt, 표 상단이 줄 상단 + 7pt, 표 왼쪽이
    /// 앞 글자 끝 + 10pt, 뒤 글자가 여백 없는 줄보다 15pt 오른쪽 — 글상자도 같다. noori 1쪽
    /// 제목 표 `vertsize` 12858 = 표 높이 12578 + 위·아래 140). 음수 여백은 0으로 본다.
    struct OuterMargins: Equatable {
        var left: CGFloat = 0
        var right: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0

        static let zero = OuterMargins()

        init(left: CGFloat = 0, right: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0) {
            self.left = left
            self.right = right
            self.top = top
            self.bottom = bottom
        }

        /// 공통 속성의 바깥 여백 — 속성이 없거나 여백 배열이 넷이 아니면 여백 없음.
        init(_ property: CoreHwp.HwpCommonCtrlProperty?) {
            guard let margins = property?.marginArray, margins.count == 4 else {
                self = .zero
                return
            }
            self.init(
                left: max(0, HwpUnits.points(fromHwpUnit16: margins[0])),
                right: max(0, HwpUnits.points(fromHwpUnit16: margins[1])),
                top: max(0, HwpUnits.points(fromHwpUnit16: margins[2])),
                bottom: max(0, HwpUnits.points(fromHwpUnit16: margins[3]))
            )
        }

        var horizontal: CGFloat {
            left + right
        }

        var vertical: CGFloat {
            top + bottom
        }
    }

    /// 글자처럼 취급 개체 자신의 원점 — 줄 앵커가 준 바깥 상자 원점(`inlineAnchorOrigin`)에서
    /// 왼쪽·위쪽 바깥 여백만큼 들어간 자리. 페이지 경로(`HwpPaginator`)와 컨테이너 경로
    /// (`HwpParagraphObjectCollector`)가 이 식을 공유한다.
    static func inlineObjectOrigin(outerBoxOrigin: CGPoint, margins: OuterMargins) -> CGPoint {
        CGPoint(x: outerBoxOrigin.x + margins.left, y: outerBoxOrigin.y + margins.top)
    }
}
