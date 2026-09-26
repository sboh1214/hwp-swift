import CoreGraphics
import CoreHwp
import Foundation

// 페이지 하단 각주 영역의 **결과 모델** — 배치 산식(`HwpFootnoteLayout`)과 갈라 둔다
// (그 파일이 SwiftLint file_length 상한 700줄에 닿았다).

public struct HwpFootnoteBlock: @unchecked Sendable, Hashable {
    /// 페이지 좌표계 (top-left origin)의 각주 영역
    public let frame: CGRect
    /// 각주 문단 (텍스트 + 지오메트리 + paraId)
    public let paragraphs: [HwpLaidOutParagraph]
    /// 각주 번호 (구역 각주 모양의 시작 번호부터 이어짐)
    public let number: Int
    /// 구분선 영역 (첫 각주 블록 위). 페이지 좌표계.
    public let separatorLine: CGRect
    /// 구분선 색
    public let separatorColor: HwpRGBColor
    /// 각주 문단 안 그림 (블록-로컬 rect, #94)
    public let images: [HwpCellImage]
    /// 각주 문단 안 도형 (블록-로컬 rect, #94)
    public let shapes: [HwpCellShape]
    /// 각주 문단 안 글상자 (블록-로컬 rect, #94)
    public let textboxes: [HwpCellTextbox]
    /// 각주 문단 안 표 (블록-로컬 rect, #94). 한글.app 실측 (헌법주석 883쪽
    /// 각주 29): 표가 각주 영역 안에 그려지고 그 아래로 다음 각주가 이어진다.
    public let nestedTables: [HwpNestedTableFrame]
    /// 이 블록이 그 각주(번호)의 **마지막 항목**인지 — 각주 영역은 문단마다 블록 하나라 같은
    /// 각주의 다음 문단은 바로 아래 블록으로 이어진다. 참이면 스택이 마지막 줄의 줄 간격을
    /// 세지 않는 자리다 (쪽 끝에서 나뉜 앞 몫도 참 — `HwpFootnoteLayout.StackEntry.isNoteEnd`,
    /// 흐름 배치도 같은 각주의 뒤 문단이 다음 쪽으로 넘어가면 이 쪽의 앞 블록이 참이다).
    /// 링크 클릭 띠의 **목록 끝**(#233 — 한글은 각주의 마지막 줄 아래를 눌러도 링크를 열지
    /// 않는다)이 이 값으로 가려진다: 참인 블록의 마지막 문단만 마지막 줄 띠가 줄 상자에서 끝난다.
    public let isNoteEnd: Bool

    public init(
        frame: CGRect,
        paragraphs: [HwpLaidOutParagraph],
        number: Int,
        separatorLine: CGRect,
        separatorColor: HwpRGBColor = HwpRGBColor(red: 0, green: 0, blue: 0),
        images: [HwpCellImage] = [],
        shapes: [HwpCellShape] = [],
        textboxes: [HwpCellTextbox] = [],
        nestedTables: [HwpNestedTableFrame] = [],
        isNoteEnd: Bool = true
    ) {
        self.frame = frame
        self.paragraphs = paragraphs
        self.number = number
        self.separatorLine = separatorLine
        self.separatorColor = separatorColor
        self.images = images
        self.shapes = shapes
        self.textboxes = textboxes
        self.nestedTables = nestedTables
        self.isNoteEnd = isNoteEnd
    }

    /// 하위 호환: 문단 지오메트리만 필요할 때
    public var paragraphFrames: [HwpParagraphFrame] {
        paragraphs.map(\.frame)
    }
}

public extension HwpFootnoteBlock {
    /// 각주가 하이퍼링크를 품는지 — 블록-레벨 폴백의 게이트 (R61)
    var hasHyperlink: Bool {
        paragraphs.contains { $0.hasHyperlink }
            || images.contains { $0.wrapperURL != nil }
            || shapes.contains { $0.wrapperURL != nil }
            || textboxes.contains { $0.wrapperURL != nil || $0.textbox.hasHyperlink }
            || nestedTables.contains { $0.wrapperURL != nil || $0.table.hasHyperlink }
    }
}
