@testable import HwpKit
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
