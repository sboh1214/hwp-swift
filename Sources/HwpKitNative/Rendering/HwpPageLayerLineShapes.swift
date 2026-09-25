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
        /// 패턴·띠·물결의 축척 (pt) — 한글 문서는 밑줄이 줄 글자 기본 크기, 취소선이 run의 글자
        /// 모양 기본 크기이고 호환 문서 두 갈래는 첨자 축소 전 run 크기다
        /// (`underlineShapeScale`·`strikethroughShapeScale`, #226)
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
    /// 열쇠가 글자 모양 id인 이유는 `msWordStrikethroughFonts`와 같다 — 속성 사전 전체 비교는
    /// 양쪽 정렬 자간·문단 끝 상자가 한 글자 모양을 가른다. 다만 같은 id 안에서도 선을
    /// 정하는 키(`sameLineShapeGroup` — 선 모양·유무·색·축척 크기·첨자 이동)가 다르면
    /// 따로 묶는다: 변경 추적 삭제 run은 글자 모양을 물려받고 색만 갈리고, 첨자 run은
    /// 취소선 자리가 달라 첫 run의 기하로 묶어 그리면 틀린다 (#191 리뷰). 슬롯마다 상대
    /// 크기가 다른 한 글자 모양도 한글 문서에서는 한 묶음이다 — 축척이 기본 크기라 슬롯이
    /// 바뀌어도 같고, 한글도 그 경계에서 위상을 잇는다 (#226, 한글 12.30 실측 2026-09-26: 기본
    /// 20pt·한글 슬롯 50%·라틴 100% "가나다라 abcdefg 마바사아"의 긴 점선 밑줄·취소선이 한 토막
    /// 5.64pt·주기 9.0pt로 슬롯 경계를 넘어 이어진다). id 없는 폴백
    /// run은 홀로 선다. 실선은 이 묶음을 쓰지 않고 run마다 그린다 (이어 붙인 사각형과
    /// 같은 결과). 선 모양 키를 실은 run이 하나도 없는 줄은 재지 않는다.
    func lineShapeSpans(of runs: [CTRun], lineOrigin: CGPoint) -> [CGRect?] {
        var spans: [CGRect?] = Array(repeating: nil, count: runs.count)
        let attributes = runs.map(runAttributes)
        guard attributes.contains(where: {
            $0[HwpAttributedStringKey.underlineShape] != nil
                || $0[HwpAttributedStringKey.strikethroughShape] != nil
        }) else { return spans }
        var groupStart = 0
        for (index, run) in runs.enumerated() {
            let bounds = runBounds(of: run, lineOrigin: lineOrigin)
            if index > 0, attributes[index][HwpAttributedStringKey.charShapeId] != nil,
               Self.sameLineShapeGroup(attributes[groupStart], attributes[index]),
               let union = spans[groupStart]
            {
                spans[groupStart] = union.union(bounds)
            } else {
                groupStart = index
                spans[index] = bounds
            }
        }
        return spans
    }

    /// `lineShapeSpans`가 한 묶음으로 보는 두 run의 조건 — 글자 모양 id와 선을 정하는 키가
    /// 모두 같다 (값 키는 수치 비교, 색은 `CFEqual`). 축척 크기 키는 그 run의 축척이 실제로
    /// 기대는 값이다: 한글 문서는 글자 모양 기본 크기(`baseFontSize` — 슬롯 상대 크기와 무관,
    /// #226), 호환 문서 두 갈래와 기본 크기 키가 없는 문자열은 슬롯 상대 크기를 반영한
    /// `spaceTargetSize`(그 갈래의 축척 — `underlineShapeScale`·`strikethroughShapeScale`).
    static func sameLineShapeGroup(
        _ lhs: [NSAttributedString.Key: Any], _ rhs: [NSAttributedString.Key: Any]
    ) -> Bool {
        var numberKeys: [NSAttributedString.Key] = [
            HwpAttributedStringKey.charShapeId,
            HwpAttributedStringKey.underlineShape, HwpAttributedStringKey.strikethroughShape,
            HwpAttributedStringKey.underlineStyle, HwpAttributedStringKey.underlineAboveStyle,
            HwpAttributedStringKey.strikethroughStyle,
            HwpAttributedStringKey.baseFontSize, HwpAttributedStringKey.scriptBaselineOffset,
            HwpAttributedStringKey.compatibleDocumentTarget,
        ]
        if shapeScaleFollowsSpaceTarget(lhs) || shapeScaleFollowsSpaceTarget(rhs) {
            numberKeys.append(HwpAttributedStringKey.spaceTargetSize)
        }
        for key in numberKeys where (lhs[key] as? NSNumber) != (rhs[key] as? NSNumber) {
            return false
        }
        let colorKeys: [NSAttributedString.Key] = [
            HwpAttributedStringKey.underlineColor, HwpAttributedStringKey.strikethroughColor,
            kCTForegroundColorAttributeName as NSAttributedString.Key,
        ]
        for key in colorKeys {
            switch (lhs[key], rhs[key]) {
            case (nil, nil):
                continue
            case let (left?, right?):
                guard CFEqual(left as CFTypeRef, right as CFTypeRef) else { return false }
            default:
                return false
            }
        }
        return true
    }

    /// 선 모양 축척이 `spaceTargetSize`(슬롯 상대 크기 반영)에 기대는 run인지 — MS 워드 호환·
    /// 한글 2007 호환 문서(그 갈래의 축척은 첨자 축소 전 run 크기)와 기본 크기 키가 없는 문자열
    /// (축척이 그 키로 떨어진다)이다.
    private static func shapeScaleFollowsSpaceTarget(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        if attributes[HwpAttributedStringKey.baseFontSize] == nil {
            return true
        }
        guard let raw = attributes[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.msWord.rawValue
            || raw.uint32Value == HwpCompatibleDocumentTarget.hwp200X.rawValue
    }

    /// 실선이 아닌 장식선 — 글자 모양 run의 폭 `span`(묶음의 첫 run만 받는다,
    /// `lineShapeSpans`; 나머지 run은 아무것도 그리지 않는다)에 `HwpLineShapeGeometry`의
    /// 경로를 편다. 패턴·띠·물결의 축척은 `shaped.fontSize`(선마다 정한 기준 크기 —
    /// `ShapedLine.fontSize`)이고, 로컬 y(양수 = 아래)를 텍스트 공간(y-위)으로 뒤집어 단선
    /// 중심(`lineOrigin.y + line.center`)에 놓는다.
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
