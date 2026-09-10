import CoreGraphics
import CoreHwp
import Foundation

// 각주 문단 높이 측정 캐시의 열쇠 — `HwpFootnoteCoordinator.swift`가 SwiftLint
// file_length 상한(700줄)에 닿아 갈라 뒀다. **`measureNote`가 받는 모든 입력이 여기
// 있어야 한다**: 하나라도 빠지면 그 축만 다른 측정이 캐시에 걸려 예약이 배치와 갈린다.

extension HwpFootnoteCoordinator {
    struct FootnoteHeightKey: Hashable {
        let paragraph: CoreHwp.HwpParagraph
        let widthCenti: Int
        /// 자동 번호 치환 텍스트가 폭에 영향을 주므로 번호도 키에 포함한다
        let number: Int
        /// 상대 크기 개체가 든 문단은 줄 높이가 해석기 기하의 함수다 — 폭만
        /// 키에 넣으면 종이/쪽 높이·단 폭만 바뀐 재사용이 살아나 예약이 배치와
        /// 갈린다 (R39 #1). 배치 (`HwpFootnoteLayout.measure`)는 캐시가 없어
        /// 항상 현재 기하로 재측정하므로 어긋나는 쪽은 언제나 예약이다.
        let sizeResolver: HwpObjectSizeResolver?
        /// `measureNote`가 받는 **모든** 입력이 키에 있어야 한다 (R54): 번호 모양
        /// (표 134) 은 자동 번호 치환 텍스트를 바꿔 첫 줄 폭 → 줄바꿈 → 블록
        /// 높이를 바꾼다. 구역이 번호를 재시작하면 (문단, 번호, 폭, 해석기) 가
        /// 모두 같으면서 모양만 다른 재사용이 살아난다.
        let footnoteShape: CoreHwp.HwpFootnoteShape?
        /// 문단 번호·개요 번호 라벨(#158)도 첫 줄 폭을 바꾼다 — 번호는 위치 경로의
        /// 함수(불변 표)라 경로가 키다. 같은 문단 값이 다른 자리에서 다른 번호를
        /// 받을 수 있으므로 문단 값만으로는 재사용을 가를 수 없다.
        let numberingPath: HwpParagraphPath?
        /// 각주의 마지막 문단인지 (#165) — 마지막 줄의 줄 간격을 세지 않는 자리라 값이 다르다.
        let noteEnd: Bool
        /// 앞 쪽에 이미 실린 줄 수 (#165) — 이어지는 조각은 그 뒤 줄만 잰다.
        let placedLineCount: Int
    }
}
