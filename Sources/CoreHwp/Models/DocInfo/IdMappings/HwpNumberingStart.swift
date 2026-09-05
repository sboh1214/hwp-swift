import Foundation

/**
 문단 번호 정의(표 38)의 시작 번호 해석 (#153).

 표 38은 시작 번호를 두 자리에 적는다 — 정의 전체의 `시작 번호`(UINT16,
 `startingIndex`)와 5.0.2.5부터 붙은 `수준별 시작번호`(UINT×7,
 `startingIndexArray`; 5.1.0.0부터는 8-10수준의 `extendedStartingIndexArray`).
 스펙은 두 값의 관계를 적지 않는다. 한컴 도움말과 실물로 확정한 의미는
 다음과 같다.

 - `startingIndex`는 **시작 번호 방식**이다. 문단 번호 대화상자의 "앞 번호
   목록에 이어 / 새 번호 목록 시작(1수준 시작 번호 입력)", 개요 번호 모양
   대화상자의 "이전 구역의 번호에 이어 / 새 번호로 시작(1수준 시작 번호 입력)"
   에 대응한다. **0이면 앞 목록(앞 구역)에 이어 매기고, 1 이상이면 새 번호로
   시작**한다. 실물: 한글.app이 새로 만든 정의(빈 문서 기본값·`outline-numbering`·
   noori의 둘째 정의)는 0이고, 헌법주석의 41개 구역이 하나씩 가리키는 41개
   정의는 첫 구역 것만 0이며 나머지 40개가 1이다 — 그 문서의 생성 목차가
   구역(조문)마다 `I.`부터 다시 세는 것과 맞물린다(수준 1 표제 280개 전부
   일치, `HwpParagraphNumberingFixtureTests`).
 - `startingIndexArray`는 새 번호로 시작할 때 **수준마다 어디서 시작하는가**다.
   배열이 없거나(5.0.2.5 미만 — 헌법주석 5.0.2.2의 정의 41개 전부) 값이
   0이면 1이다. 1수준은 두 자리 모두에 적힐 수 있어(`startingIndex`가 새 번호
   N이면서 배열의 첫 값이 1이거나 그 반대) **둘 중 큰 값**을 쓴다 — 한 값만
   1보다 크면 그것이 사용자가 적은 시작 번호이고, 둘 다 1이면 1이다.
   한글.app이 새 번호 N을 어느 자리에 적는지는 아직 실측하지 못했다(2026-09-06
   GUI 접근 거부) — 두 인코딩 모두 같은 결과를 내도록 둔 것이다.

 카운터가 이 값을 언제 쓰는지(구역 경계·정의 교체)는 HwpKitCore의
 `HwpParagraphNumbering`이 정한다.
 */
public extension HwpNumbering {
    /// 시작 번호 방식 — `startingIndex`가 0이면 앞 번호 목록(개요는 이전 구역)에
    /// 이어 매기고, 1 이상이면 이 정의로 바뀌는 자리에서 새 번호로 시작한다.
    var continuesPreviousList: Bool {
        startingIndex == 0
    }

    /// 사람이 읽는 수준(1-10)이 새 번호로 시작할 때의 첫 번호. 수준별 시작번호가
    /// 없거나 0이면 1이고, 1수준은 `startingIndex`와 수준별 값 중 큰 쪽이다.
    /// 범위 밖 수준은 1이다.
    func startingNumber(forLevel level: Int) -> Int {
        let perLevel: UInt32? = if (1 ... 7).contains(level) {
            startingIndexArray.flatMap { $0.indices.contains(level - 1) ? $0[level - 1] : nil }
        } else if (8 ... 10).contains(level) {
            extendedStartingIndexArray.flatMap {
                $0.indices.contains(level - 8) ? $0[level - 8] : nil
            }
        } else {
            nil
        }
        let levelStart = max(1, Int(perLevel ?? 1))
        guard level == 1 else { return levelStart }
        return max(levelStart, Int(startingIndex))
    }
}
