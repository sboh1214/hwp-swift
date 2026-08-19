@testable import HwpKit
import HwpKitCore
import Nimble
import SwiftUI
import XCTest

/// 툴바 크롬 VoiceOver 라벨 (#79) — `-`·`+`·`‹`·`›` 는 문장부호라 VoiceOver 가
/// 문맥 없이 읽거나 건너뛴다. 라벨은 `String` 계산 프로퍼티다
/// (`LocalizedStringKey` 는 키 문자열을 꺼낼 공개 경로가 없어 문구를 테스트로
/// 고정할 수 없다). 컴포넌트마다 body 를 실제로 평가해 라벨이 달린 분기까지
/// 커버한다.
final class HwpAccessibilityLabelTests: XCTestCase {
    @MainActor
    func testZoomControlsExposeAccessibilityLabels() {
        var zoomScale = CGFloat(1.0)
        var fitZoom: HwpZoomFit?
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            // fit 바인딩을 넘겨야 맞춤 버튼 분기의 라벨까지 body 평가에 잡힌다.
            fitZoom: Binding(get: { fitZoom }, set: { fitZoom = $0 })
        )

        expect(String(describing: controls.body)).toNot(beEmpty())
        expect(controls.zoomOutAccessibilityLabel) == "축소"
        expect(controls.zoomInAccessibilityLabel) == "확대"
        expect(controls.resetZoomAccessibilityLabel) == "배율 초기화"
        expect(controls.fitWidthAccessibilityLabel) == "폭 맞춤"
        expect(controls.fitPageAccessibilityLabel) == "쪽 맞춤"
    }

    @MainActor
    func testPageNavigatorExposesAccessibilityLabels() {
        var page = 2
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )

        expect(String(describing: navigator.body)).toNot(beEmpty())
        expect(navigator.previousPageAccessibilityLabel) == "이전 쪽"
        expect(navigator.nextPageAccessibilityLabel) == "다음 쪽"
    }

    @MainActor
    func testSearchNavigatorExposesAccessibilityLabels() {
        let navigator = HwpSearchNavigator(controller: HwpSearchController())

        expect(String(describing: navigator.body)).toNot(beEmpty())
        expect(navigator.previousMatchAccessibilityLabel) == "이전 검색 결과"
        expect(navigator.nextMatchAccessibilityLabel) == "다음 검색 결과"
    }

    @MainActor
    func testSearchBarExposesAccessibilityLabels() {
        let controller = HwpSearchController()
        // 질의를 넣고 onDismiss 를 줘야 Clear·Done 버튼 분기가 body 에 나타난다.
        controller.search(text: "질의")
        let bar = HwpSearchBar(controller: controller, onDismiss: {})

        expect(String(describing: bar.body)).toNot(beEmpty())
        expect(bar.clearAccessibilityLabel) == "검색어 지우기"
        expect(bar.dismissAccessibilityLabel) == "검색 닫기"
    }

    /// 11개 버튼 라벨은 상호 구별되어야 한다 — 두 컴포넌트의 `-`/`+` 처럼
    /// 같은 표시 문구가 다른 뜻으로 쓰이는 자리가 라벨에서 겹치면 VoiceOver
    /// 사용자는 어느 버튼인지 구분할 수 없다.
    @MainActor
    func testAccessibilityLabelsAreMutuallyDistinct() {
        var zoomScale = CGFloat(1.0)
        var fitZoom: HwpZoomFit?
        var page = 1
        let zoom = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            fitZoom: Binding(get: { fitZoom }, set: { fitZoom = $0 })
        )
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )
        let controller = HwpSearchController()
        let searchNavigator = HwpSearchNavigator(controller: controller)
        let searchBar = HwpSearchBar(controller: controller, onDismiss: {})

        let labels = [
            zoom.zoomOutAccessibilityLabel,
            zoom.zoomInAccessibilityLabel,
            zoom.resetZoomAccessibilityLabel,
            zoom.fitWidthAccessibilityLabel,
            zoom.fitPageAccessibilityLabel,
            navigator.previousPageAccessibilityLabel,
            navigator.nextPageAccessibilityLabel,
            searchNavigator.previousMatchAccessibilityLabel,
            searchNavigator.nextMatchAccessibilityLabel,
            searchBar.clearAccessibilityLabel,
            searchBar.dismissAccessibilityLabel,
        ]

        expect(labels.allSatisfy { !$0.isEmpty }) == true
        expect(Set(labels).count) == labels.count
    }
}
