import Foundation

/// 문단의 **위치 경로** — 최상위 본문 문단의 위치 열쇠(`HwpParagraphKey`)에
/// 컨테이너 안 문단으로 내려가는 단계를 이어 붙인 것 (#153).
///
/// 문단 번호·개요 번호는 표 셀·글상자·각주 안 문단에도 붙으므로 결과를
/// 최상위 열쇠만으로는 조회할 수 없다. `paraId`는 한글.app 저장본에서
/// 0·0x80000000이 되풀이돼 문단을 가르지 못하니(#145) 쓰지 않고, 조판이 컨테이너
/// 문단을 방문하는 **같은 순서**(`HwpPaginator.childParagraphs(of:)`)의 서수로
/// 단계를 적는다 — 위치는 문서 순서의 함수라 같은 문단을 몇 번 재측정·재배치해도
/// 같은 경로가 나온다.
public struct HwpParagraphPath: Hashable, Sendable {
    /// 컨테이너 한 겹 — 부모 문단의 `ctrlHeaderArray` 안 컨트롤 서수와, 그
    /// 컨트롤의 자식 문단 목록(`HwpPaginator.childParagraphs(of:)` — 표는 셀을
    /// 차례로 펼친 문단 목록, 개체는 글상자 목록을 펼친 문단 목록) 안 서수.
    public struct Step: Hashable, Sendable {
        public let controlIndex: Int
        public let childIndex: Int

        public init(controlIndex: Int, childIndex: Int) {
            self.controlIndex = controlIndex
            self.childIndex = childIndex
        }
    }

    /// 최상위 본문 문단의 위치 열쇠 — 컨테이너 안 문단이면 그 컨테이너를 품은
    /// 본문 문단이다.
    public let paragraph: HwpParagraphKey
    /// 본문 문단에서 이 문단까지 내려가는 단계 — 최상위 문단이면 비어 있다.
    public let steps: [Step]

    public init(paragraph: HwpParagraphKey, steps: [Step] = []) {
        self.paragraph = paragraph
        self.steps = steps
    }

    /// 최상위 본문 문단의 경로.
    public init(sectionIndex: Int, paragraphIndex: Int) {
        self.init(paragraph: HwpParagraphKey(
            sectionIndex: sectionIndex, paragraphIndex: paragraphIndex
        ))
    }

    /// 최상위 본문 문단인가.
    public var isTopLevel: Bool {
        steps.isEmpty
    }

    /// 이 문단의 `controlIndex`번째 컨트롤이 품은 `childIndex`번째 자식 문단의 경로.
    public func appending(controlIndex: Int, childIndex: Int) -> HwpParagraphPath {
        HwpParagraphPath(
            paragraph: paragraph,
            steps: steps + [Step(controlIndex: controlIndex, childIndex: childIndex)]
        )
    }
}

extension HwpParagraphPath: CustomStringConvertible {
    /// `s0/p378` · `s0/p12/c1/n3` — 스냅샷과 진단이 읽는 표기.
    public var description: String {
        var text = "s\(paragraph.sectionIndex)/p\(paragraph.paragraphIndex)"
        for step in steps {
            text += "/c\(step.controlIndex)/n\(step.childIndex)"
        }
        return text
    }
}
