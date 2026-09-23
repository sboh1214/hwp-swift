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

extension HwpParagraphLayout {
    /// 컨트롤마다 그것을 실은 줄 캐시 세그먼트의 색인 (controlIndex 순) — 컨트롤 문자의 WCHAR
    /// 위치를 덮는 마지막 세그먼트다. 확장 컨트롤 문자 수가 컨트롤 수와 달라 위치를 못 풀면 nil,
    /// 첫 세그먼트보다 앞에 놓인 컨트롤은 원소가 nil이다.
    static func controlHostSegments(of paragraph: CoreHwp.HwpParagraph) -> [Int?]? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard let ctrls = paragraph.ctrlHeaderArray else { return nil }
        var offsets: [Int] = []
        var offset = 0
        for char in paragraph.paraText?.charArray ?? [] {
            if char.type == .extended {
                offsets.append(offset)
            }
            offset += char.type == .char ? 1 : 8
        }
        guard offsets.count == ctrls.count else { return nil }
        return offsets.map { offset in
            segments.lastIndex { Int($0.textStartingIndex) <= offset }
        }
    }

    /// 문단의 줄 캐시가 글자처럼 취급 표보다 낡았는가 (#214 리뷰) — 한글이 저장한 캐시에서 표를
    /// 실은 줄의 높이(`vertsize`)는 그 표의 바깥 상자(표 + 위·아래 바깥 여백) 이상이다. 그보다
    /// 낮으면 저작 뒤 셀 내용이 표를 키운 문서라, 줄 예약이 그려지는 높이인 지금(#214) 표 줄이
    /// 커지며 그 아래 줄과 뒤 문단이 모두 내려간다 — 캐시 높이를 믿으면 표가 뒤 줄·문단을 덮는다.
    /// 한글도 그런 문서를 열 때 캐시를 버리고 다시 조판한다 (한글 12.30 실측: 한글이 저장한 문서의
    /// 4행 표 셀마다 문단 다섯을 더한 사본 — 표 51.28 → 371.28pt — 은 호스트 줄 캐시가 56.94pt로
    /// 남아 있어도 표 줄을 376.94pt로 키우고 뒤 문단을 그만큼 내려 그린다).
    ///
    /// 본문 흐름 배치(`HwpPaginator.lineCacheHeightIsUsable`)·다단 캐시 run·절대 캐시의 낡은 캐시
    /// 보정·각주 측정(`HwpFootnoteLayout.measureNote`)이 같은 술어를 쓴다. 위치를 못 푸는 문단은
    /// 가장 높은 캐시 줄과 견준다. `tableHeights`는 표 높이(바깥 여백 제외, pt)다. 우리 레이아웃
    /// 높이를 믿을 수 없는 표(`rowsHaveOwnCells`가 거짓)는 견주지 않는다.
    static func lineCacheIsStale(
        _ paragraph: CoreHwp.HwpParagraph,
        inlineTableHeights tableHeights: [Int: CGFloat]
    ) -> Bool {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !tableHeights.isEmpty, !segments.isEmpty, let ctrls = paragraph.ctrlHeaderArray
        else { return false }
        let hosts = controlHostSegments(of: paragraph)
        let tallest = segments.map(\.lineHeight).max() ?? 0
        for (ordinal, height) in tableHeights where ctrls.indices.contains(ordinal) {
            guard case let .table(table) = ctrls[ordinal], rowsHaveOwnCells(table) else { continue }
            let margins = HwpObjectAnchorGeometry.OuterMargins(table.commonCtrlProperty)
            let lineHeight = hosts?[ordinal].map { segments[$0].lineHeight } ?? tallest
            if height + margins.vertical > HwpUnits.points(fromHwpUnit: lineHeight) + 0.5 {
                return true
            }
        }
        return false
    }

    /// 표의 모든 행에 그 행 하나만 차지하는 셀이 있는가 (#214 PR 리뷰) — 행 병합으로만 덮인 행은 우리
    /// 표 레이아웃이 셀 안쪽 여백만큼의 기본 높이를 얹고 병합 셀의 모자란 몫을 마지막 행에 몰아
    /// (`HwpTableLayoutFrames.resolvedRowHeights`) 한글보다 높게 잡을 수 있다 — 두 행을 합친 이름 칸
    /// 옆에 두 행을 합친 값 칸이 있는 양식 꼴이다(1열 2행을 합친 표: 한글 20pt, 우리 22.82pt). 그런 표의
    /// 레이아웃 높이로 캐시를 견주면 한글이 저장한 신선한 캐시를 낡았다고 오판해 뒤 문단을 밀므로
    /// 판정에서 뺀다 — 그 표가 저장 뒤에 커진 문서는 종전처럼 캐시를 따른다. 셀 속성이 없어 주소를 모르는
    /// 셀이 있으면 가를 수 없으니 거짓이다.
    static func rowsHaveOwnCells(_ table: CoreHwp.HwpTable) -> Bool {
        guard let grid = HwpTableLayout.grid(of: table) else { return false }
        var rows = Set<Int>()
        for cell in table.cellArray {
            guard let property = cell.header.cellProperty else { return false }
            if property.rowSpan <= 1 {
                rows.insert(Int(property.rowAddress))
            }
        }
        return (0 ..< grid.rows).allSatisfy(rows.contains)
    }
}
