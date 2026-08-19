@testable import HwpKit
import HwpKitCore
import Nimble
import SwiftUI
import XCTest

final class HwpToolsTests: XCTestCase {
    @MainActor
    func testToolbarHostsContent() {
        let toolbar = HwpDocumentToolbar {
            Text(LocalizedStringKey("Tools"))
        }

        expect(String(describing: type(of: toolbar.body))).toNot(beEmpty())
    }

    @MainActor
    func testPageNavigatorIncrementsCurrentPage() {
        var page = 1
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )

        navigator.incrementPage()

        expect(page) == 2
    }

    @MainActor
    func testPageNavigatorDoesNotIncrementPastTotalPages() {
        var page = 3
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )

        navigator.incrementPage()

        expect(page) == 3
    }

    @MainActor
    func testZoomControlsClampToUpperBound() {
        var zoomScale = CGFloat(1.0)
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            range: 0.25 ... 5.0
        )

        controls.setZoomScale(10)

        expect(zoomScale) == 5.0
    }

    @MainActor
    func testZoomControlsResetToOne() {
        var zoomScale = CGFloat(2.0)
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 })
        )

        controls.resetZoom()

        expect(zoomScale) == 1.0
    }

    /// 맞춤 버튼은 **명령만** 세운다 — 실제 배율은 뷰포트를 아는 문서 뷰가
    /// 정해 `zoomScale`로 되돌려주므로, 여기서 배율을 미리 건드리면 뷰가 아직
    /// 맞추지 못한 순간에 라벨이 거짓말을 한다 (#78).
    @MainActor
    func testZoomControlsFitButtonsSetTheCommandWithoutTouchingScale() {
        var zoomScale = CGFloat(2.0)
        var fitZoom: HwpZoomFit?
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            fitZoom: Binding(get: { fitZoom }, set: { fitZoom = $0 })
        )

        controls.requestFit(.width)
        expect(fitZoom) == HwpZoomFit.width
        expect(zoomScale) == 2.0

        controls.requestFit(.page)
        expect(fitZoom) == HwpZoomFit.page
        expect(zoomScale) == 2.0
    }

    /// 맞춤 바인딩을 안 넘긴 호스트(기존 호출부)에서는 눌러도 아무 일이
    /// 일어나지 않는 버튼을 만들지 않는다 — 명령 자체가 무동작이다.
    @MainActor
    func testZoomControlsWithoutFitBindingIgnoreFitRequests() {
        var zoomScale = CGFloat(1.0)
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 })
        )

        controls.requestFit(.width)

        expect(zoomScale) == 1.0
        expect(String(describing: type(of: controls.body))).toNot(beEmpty())
    }

    /// 비-finite 바인딩은 표시의 Int 변환·쓰기 경로 모두에서 트랩 없이
    /// 리셋 기본값으로 폴백해야 한다 — min/max 클램프는 NaN을 통과시킨다 (R57 #2).
    @MainActor
    func testZoomControlsSanitizeNonFiniteAndExtremeValues() {
        var zoomScale = CGFloat.nan
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            range: 0.25 ... 5.0
        )

        expect(controls.sanitized(.nan)) == 1.0
        expect(controls.sanitized(.infinity)) == 1.0
        expect(controls.sanitized(-.infinity)) == 1.0
        expect(controls.sanitized(.greatestFiniteMagnitude)) == 5.0
        expect(controls.sanitized(-.greatestFiniteMagnitude)) == 0.25
        expect(controls.sanitized(2.0)) == 2.0

        controls.setZoomScale(.nan)
        expect(zoomScale) == 1.0
    }
}
