import CoreGraphics
import Foundation
import HwpKitCore

/// 페이지별 합성 접근성 요소 보관함 — macOS/iOS 문서 뷰가 공유한다 (#79).
/// 요소 타입은 플랫폼이 정하므로 (`NSAccessibilityElement`/
/// `UIAccessibilityElement`) 제네릭이고, 이 파일은 `#if` 밖이라 macOS 빌드에
/// 포함되어 swift test 가 커버한다 (`HwpSelectionHandleGeometry` 와 같은 틀).
///
/// 요소는 만들 때의 페이지 레이어 frame (`anchorFrame`) 에 좌표를 박아 두므로,
/// frame 이 움직였으면 (프로그레시브 로딩이 콘텐츠 폭을 키워 가운데 정렬
/// x 가 밀리는 경우) 그 페이지 요소를 다시 만들어야 한다 — 조회가 anchor 를
/// 함께 받는 이유다. 문서 didSet 의 전량 무효화가 1차 방어선이고 이 대조는
/// `selectionLayers` 청소와 같은 성격의 2차 방어선이다.
@MainActor
final class HwpDocumentAccessibilityStore<Element: AnyObject> {
    private struct PageEntry {
        let anchorFrame: CGRect
        let elements: [Element]
    }

    private var entries: [Int: PageEntry] = [:]

    /// 그 페이지 요소 — anchor frame 이 지금과 다르면 nil (재생성 신호).
    func elements(forPage pageIndex: Int, anchoredTo frame: CGRect) -> [Element]? {
        guard let entry = entries[pageIndex], entry.anchorFrame == frame else { return nil }
        return entry.elements
    }

    /// 테스트·평탄화용 무조건 조회.
    func elements(forPage pageIndex: Int) -> [Element]? {
        entries[pageIndex]?.elements
    }

    func setElements(_ elements: [Element], forPage pageIndex: Int, anchoredTo frame: CGRect) {
        entries[pageIndex] = PageEntry(anchorFrame: frame, elements: elements)
    }

    /// 레이어 가상화와 동기로 실체화 페이지 밖 요소를 버린다.
    func prune(keeping pages: some Collection<Int>) {
        let keep = Set(pages)
        for pageIndex in entries.keys where !keep.contains(pageIndex) {
            entries[pageIndex] = nil
        }
    }

    /// 문서 스냅샷 교체·전체 교체 — stale 라벨이 남지 않게 전량 버린다.
    func removeAll() {
        entries.removeAll()
    }

    var pageIndices: [Int] {
        Array(entries.keys)
    }

    /// 컨테이너에 대입할 평탄화 목록 — 페이지 순서가 곧 낭독 순서다.
    var flattenedInPageOrder: [Element] {
        entries.keys.sorted().flatMap { entries[$0]?.elements ?? [] }
    }
}

/// 문서 → 접근성 모델 합성의 뷰 공통 진입점 (#79). 합성 자체는 HwpKitCore 의
/// `HwpAccessibilityContent` 가 하고, 여기는 쪽별 개요 제목 선별과 본문 단위
/// 폴백만 얹는다.
enum HwpDocumentAccessibility {
    /// 페이지 하나의 (페이지 로컬, 메모 패널 로컬) 모델 묶음.
    ///
    /// - Parameter bodyUnits: 뷰가 가진 `HwpSelectionGeometry.units(forPage:)`
    ///   캐시. nil 이면 (선택 컨트롤러가 아직 문서를 못 받은 창) 직접 전개한다.
    nonisolated static func units(
        document: HwpDocument?,
        pageIndex: Int,
        bodyUnits: [HwpTextUnit]?
    ) -> (page: [HwpAccessibilityUnit], memo: [HwpAccessibilityUnit]) {
        guard let document, let page = document.pages[safe: pageIndex] else {
            return ([], [])
        }
        // 개요는 프로그레시브 중간 스냅샷에도 확정된 접두가 실리므로 로딩
        // 중에도 그대로 쓴다 — 총 쪽수 같은 확정값을 여기서 알리지는 않는다.
        let headingTitles = document.metadata.outline
            .filter { $0.kind == .heading && $0.pageIndex == pageIndex }
            .map(\.title)
        let pageUnits = HwpAccessibilityContent.pageUnits(
            page: page,
            bodyUnits: bodyUnits ?? HwpSelectableText.units(in: page),
            headingTitles: headingTitles
        )
        let memoUnits = page.memoPanel.map(HwpAccessibilityContent.memoPanelUnits) ?? []
        return (pageUnits, memoUnits)
    }
}
