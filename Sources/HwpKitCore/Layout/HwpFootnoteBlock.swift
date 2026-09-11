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

    public init(
        frame: CGRect,
        paragraphs: [HwpLaidOutParagraph],
        number: Int,
        separatorLine: CGRect,
        separatorColor: HwpRGBColor = HwpRGBColor(red: 0, green: 0, blue: 0),
        images: [HwpCellImage] = [],
        shapes: [HwpCellShape] = [],
        textboxes: [HwpCellTextbox] = [],
        nestedTables: [HwpNestedTableFrame] = []
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
