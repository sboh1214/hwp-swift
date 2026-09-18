import CoreHwp
import Foundation

extension HwpTextRunBuilder {
    /// 문단 밖 한 줄 문자열 — 쪽 번호처럼 문단 없이 글자 모양 하나로 조판하는 글자.
    ///
    /// 본문 글자와 같은 chunk 경로를 **글자마다** 지난다 — `accumulate`는 호출 단위로 첫
    /// 스칼라의 스크립트를 판정하므로 통째로 넘기면 첫 글자의 슬롯이 전부를 덮는다(문단
    /// 번호 라벨 선례, `appendNumberingHeading`). 그래서 숫자·줄표·빈칸이 각자의 스크립트
    /// 슬롯 글꼴·상대 크기·장평·자간·빈칸 폭 규칙을 따르고, 줄 상자 기준 크기
    /// (`HwpAttributedStringKey.baseFontSize`)도 실린다. 문단 모양은 달지 않는다.
    func standaloneRun(_ text: String, charShapeId: UInt32) -> NSMutableAttributedString {
        let paragraph = CoreHwp.HwpParagraph()
        let output = NSMutableAttributedString()
        var chunk = Chunk(shapeId: charShapeId, script: nil)
        for character in text {
            accumulate(
                String(character), shapeId: charShapeId, into: &chunk,
                paragraph: paragraph, to: output
            )
        }
        append(chunk, paragraph: paragraph, to: output)
        return output
    }
}
