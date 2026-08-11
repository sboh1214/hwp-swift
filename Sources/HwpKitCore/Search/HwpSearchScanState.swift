import Foundation

/// 스캔의 **내부 표현** — 컨트롤러 본문에서 갈라 둔다.
///
/// 이 타입들은 컨트롤러의 저장 프로퍼티를 하나도 건드리지 않으므로, 파일을
/// 옮겨도 접근 수준을 느슨하게 할 필요가 없다 (`scanBatch` 같은 메서드는
/// `scannedPageCount` 의 private setter 를 쓰기 때문에 옮길 수 없다).
extension HwpSearchController {
    /// 스캔이 페이지를 넘나들며 들고 다니는 누적 상태 — 하이라이트 전량과
    /// dedup 된 목록, 그리고 그 목록에 기여한 문단들.
    ///
    /// 기여 집합을 목록에서 **파생**시켜 둘이 어긋날 여지를 없앤다: dedup 은
    /// "이 문단이 이미 목록에 기여했는가"로 판정하므로, 집합이 목록과 갈리면
    /// 클론이 원본 행세를 하거나 원본이 클론으로 몰려 사라진다.
    struct ScanState {
        var collected: [HwpSearchMatch]
        var navigable: [HwpSearchMatch]
        var contributedParagraphIds: Set<UInt32>

        init(collected: [HwpSearchMatch], navigable: [HwpSearchMatch]) {
            self.collected = collected
            self.navigable = navigable
            contributedParagraphIds = Set(navigable.compactMap(\.paragraphId))
        }
    }

    /// 배치 하나의 결과. `.finished` 는 최종 발행까지 마친 상태다.
    enum ScanOutcome {
        case needsYield
        case finished
        case cancelled
    }

    /// 배치 사이에 태스크 본문이 들고 다니는 진행 상태.
    ///
    /// 컨트롤러 프로퍼티가 아니라 **태스크 프레임**에 산다 — 스캔 하나에만
    /// 의미가 있고, 프로퍼티로 올리면 취소된 스캔의 잔재가 다음 스캔에 섞인다.
    struct ScanProgress {
        let query: HwpSearchQuery
        var state: ScanState
        var scannedThrough: Int
        var nextPage: Int
    }
}
