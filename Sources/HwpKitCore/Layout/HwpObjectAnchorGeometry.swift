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
    /// 세로는 줄 상자 모델(#178·#180)을 따른다: `line.origin.y`는 그 줄 **상자 상단**(문단
    /// 첫 줄 상자 상단 기준)이고 `line.baseline`은 상자 상단에서 베이스라인 앵커까지의 거리
    /// (`HwpDrawnTextLayout.baselineAnchor`)다. 개체의 **바깥 상자**(개체 + 바깥 여백, 높이
    /// `anchor.ascent`)는 그 높이의 글자 하나처럼 놓인다 — 바깥 상자 상단에서 높이 ×
    /// `line.objectBaselineRatio` 내려간 자리가 줄 베이스라인에 맞는다 (#195). 한글 문서는 글자
    /// 상자와 같은 0.85(`HwpRenderTuning.Text.baselineAnchorRatio`), MS 워드 호환 문서는
    /// 1(바깥 상자 바닥이 베이스라인) — `HwpLineFrame.objectBaselineRatio`가 줄마다 든다.
    ///
    /// 개체가 상자를 정한 줄(코퍼스의 전부)에서는 종전과 같은 자리다 — 상자 높이 = 바깥 상자
    /// 높이라 `baseline` = 비율 × `ascent`이고 바깥 상자 상단 = 상자 상단이다. 상자보다
    /// 작은 개체는 종전에 바깥 상자 **바닥**을 베이스라인에 두어 한글보다 (1 − 비율) × 높이만큼
    /// 위였다 (이슈 #195: 함초롬바탕 40pt 줄의 20pt 그림 −2.99pt, 30pt −4.55pt).
    ///
    /// 한글 12.30 실측 (2026-09-21, 합성 HWPX → 한글 PDF, 전부 0.12pt 안): 함초롬바탕 40pt
    /// 160% 줄에 폭 40pt 그림 높이 4·8·20·30·36·40·50pt → 그림 상단 = 베이스라인 − 0.85 ×
    /// 높이(3.49·6.85·16.93·25.57·30.62·33.98·42.62). 바깥 여백 위 7·아래 3pt(바깥 30)의
    /// 20pt 그림은 바깥 상자 상단 = 베이스라인 − 25.5, 그림은 그 아래 7; 위 0·아래 10과
    /// 위 10·아래 0, 위·아래 15(바깥 50 > 상자 40)도 같은 식. 마커 run·본문의 상대 크기
    /// 50·150%, 줄 간격 100%·고정 30·60pt·여백만 0·최소 50pt, Apple SD 산돌고딕 Neo, 가운데
    /// 정렬, 한 줄의 8·20·30pt 세 그림, 10pt 줄의 4·8·20pt 그림, 20pt 줄의 10·20pt 그림,
    /// 도형(사각형 20·50pt)·글상자·표 셀 안·글상자 안·쪽에 걸친 문단의 둘째 쪽 조각까지 모두
    /// 0.85. MS 워드 호환 문서(함초롬돋움 40pt)는 같은 표본 전부 베이스라인 − 높이(4.0·8.05·
    /// 19.93·30.02·36.02·40.11·50.04, 여백 위 7·아래 3은 − 23.05 = 바깥 바닥 − 3).
    ///
    /// 결과는 줄이 예약한 **바깥 상자**(`OuterMargins`)의 원점이다 — 개체 자신의 원점은
    /// `inlineObjectOrigin`이 여백만큼 들여 낸다. 바깥 상자가 베이스라인 위 공간보다 커도 상자
    /// 상단 위로는 올리지 않는다 — 측정 줄 프레임은 `baseline` ≥ 비율 × `ascent`라 이 가드에
    /// 걸리지 않고, 줄 프레임을 손으로 만든 입력만 막는다. 두 경로가 이 식을 공유한다.
    static func inlineAnchorOrigin(
        paragraphOrigin: CGPoint,
        line: HwpLineFrame,
        anchor: HwpInlineAnchor
    ) -> CGPoint {
        let drop = max(0, line.baseline - line.objectBaselineRatio * anchor.ascent)
        return CGPoint(
            x: paragraphOrigin.x + line.origin.x + anchor.xOffset,
            y: paragraphOrigin.y + line.origin.y + drop
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
