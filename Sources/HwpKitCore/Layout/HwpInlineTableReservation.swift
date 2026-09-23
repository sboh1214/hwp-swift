import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 글자처럼 취급 표의 줄 예약 높이 (#214)

//
// 글자처럼 취급 표의 줄 예약은 **그려지는 높이**다 (`HwpTextRunBuilder.inlineObjectReservation`)
// — 셀 내용이 행을 키운 표를 저작 높이로 예약하면 줄이 표보다 작아 뒤 문단이 표를 덮는다.
// 조판 문자열을 만들기 전에 표를 조판해야 하므로, 본문 경로는 측정 직전에 문단의 글자처럼
// 취급 표를 조판해 그 높이를 빌더에 넘기고(`inlineTableHeights(for:)`), 배치가 같은 표를 다시
// 조판하지 않게 결과를 문단 단위로 메모한다(`InlineTableFrameMemo`).

extension HwpTableFrame {
    /// 흐름 경로(`HwpPaginator`의 줄 안 표·글 앞/뒤로 표)가 표 블록으로 그리는 높이 — 가장
    /// 아래 행 프레임의 바닥이다. 줄 예약(#214)과 블록이 같은 값을 써야 표가 줄을 넘치지 않는다.
    var flowBlockHeight: CGFloat {
        rows.reduce(CGFloat(0)) { max($0, $1.rowFrame.maxY) }
    }
}

/// 최상위 문단 하나의 글자처럼 취급 표 레이아웃 메모 (#214).
///
/// 표 레이아웃은 (표, 가용 폭, 크기 해석기, 셀 번호 경로)의 순수 함수라 열쇠가 같으면 결과가
/// 같다 — 표는 문단 경로와 컨트롤 서수로 특정한다. 문단이 바뀌면(`owner`) 통째로 비워 메모가
/// 문단 하나 몫만 들고 있게 한다. 쪽을 넘겨 같은 문단을 다시 처리할 때(`measureMemo`와 같은
/// 경우)는 그대로 쓴다.
struct InlineTableFrameMemo {
    struct Key: Hashable {
        let hostPath: HwpParagraphPath
        let controlIndex: Int
        let availableWidth: CGFloat
        let sizeResolver: HwpObjectSizeResolver
    }

    private var owner: HwpParagraphPath?
    private var frames: [Key: HwpTableFrame] = [:]

    func frame(for key: Key, owner current: HwpParagraphPath) -> HwpTableFrame? {
        guard owner == current else { return nil }
        return frames[key]
    }

    mutating func store(_ frame: HwpTableFrame, for key: Key, owner current: HwpParagraphPath) {
        if owner != current {
            frames = [:]
            owner = current
        }
        frames[key] = frame
    }
}

extension HwpTableLayout {
    /// 문단의 글자처럼 취급 표가 **컨테이너 줄 앵커에** 그려질 높이 (controlIndex → pt, #214) —
    /// 표를 그 자리에 그리는 컨테이너(각주·미주: `HwpParagraphObjectCollector.table`)가 문단을
    /// 재기 전에 부른다. 수집기와 같은 입력(문단 폭·크기 해석기·클램프·셀 번호 경로)·같은
    /// 높이(외곽 높이)라 줄 예약과 그림이 갈리지 않는다. 조판이 실패한 표는 싣지 않는다.
    func inlineTableHeights(
        in paragraph: CoreHwp.HwpParagraph,
        availableWidth: CGFloat,
        index: HwpIndex,
        sizeResolver: HwpObjectSizeResolver?,
        numbering: HwpNumberingScope?
    ) -> [Int: CGFloat] {
        guard let ctrls = paragraph.ctrlHeaderArray else { return [:] }
        var heights: [Int: CGFloat] = [:]
        for (ordinal, ctrl) in ctrls.enumerated() {
            guard case let .table(table) = ctrl,
                  table.commonCtrlProperty.propertyInfo.treatAsChar,
                  case let .success(frame) = layout(
                      table: table,
                      availableWidth: availableWidth,
                      index: index,
                      sizeResolver: sizeResolver,
                      clampToAvailableWidth: true,
                      numbering: numbering?.container(controlIndex: ordinal)
                  )
            else { continue }
            heights[ordinal] = frame.outerFrame.height
        }
        return heights
    }
}
