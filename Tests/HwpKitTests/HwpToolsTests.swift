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
    func testPageNavigatorDecrementsCurrentPage() {
        var page = 2
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )

        navigator.decrementPage()

        expect(page) == 1
    }

    @MainActor
    func testPageNavigatorDoesNotDecrementBelowOne() {
        var page = 1
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 3
        )

        navigator.decrementPage()

        expect(page) == 1
    }

    // MARK: - 페이지 번호 입력 확정 (#120)

    /// 커밋은 `1...totalPages` 클램프를 지나 바인딩에 쓴다. 사용자가 흘린
    /// 앞뒤 공백은 무효가 아니라 입력의 일부로 받는다.
    @MainActor
    func testPageEntryCommitWritesClampedPage() {
        var page = 1
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 5
        )

        navigator.commitPageEntry("3")
        expect(page) == 3

        navigator.commitPageEntry(" 4 ")
        expect(page) == 4

        navigator.commitPageEntry("999")
        expect(page) == 5

        navigator.commitPageEntry("0")
        expect(page) == 1

        navigator.commitPageEntry("-7")
        expect(page) == 1
    }

    /// 숫자가 아닌 입력·오버플로 입력은 바인딩을 건드리지 않는다 — 되돌림은
    /// 뷰의 초안 동기화 몫이고, 이 계층은 쓰지 않는 것으로 답한다.
    @MainActor
    func testPageEntryCommitIgnoresNonNumericInput() {
        var page = 3
        var writeCount = 0
        let navigator = HwpPageNavigator(
            currentPage: Binding(
                get: { page },
                set: { newValue in
                    page = newValue
                    writeCount += 1
                }
            ),
            totalPages: 5
        )

        navigator.commitPageEntry("abc")
        navigator.commitPageEntry("")
        navigator.commitPageEntry("12쪽")
        // Int 표현 범위를 넘는 자릿수도 트랩 없이 무효 처리된다.
        navigator.commitPageEntry("99999999999999999999")

        expect(page) == 3
        expect(writeCount) == 0
    }

    /// 현재 쪽과 같은 값으로의 커밋은 재쓰기를 생략한다 — SwiftUI 갱신 루프에
    /// 무의미한 상태 쓰기를 넣지 않는다 (`handlePageChanged`의 동치 가드와
    /// 같은 성격).
    @MainActor
    func testPageEntryCommitSkipsWritingAnUnchangedPage() {
        var page = 5
        var writeCount = 0
        let navigator = HwpPageNavigator(
            currentPage: Binding(
                get: { page },
                set: { newValue in
                    page = newValue
                    writeCount += 1
                }
            ),
            totalPages: 5
        )

        navigator.commitPageEntry("5")
        // 클램프 결과가 현재 쪽과 같아도 마찬가지다.
        navigator.commitPageEntry("999")

        expect(page) == 5
        expect(writeCount) == 0
    }

    /// `totalPages`가 0인 호스트(빈 문서를 그대로 넘긴 경우)에서도 하한 1이
    /// 선다 — 상한 `max(1, totalPages)` 계약.
    @MainActor
    func testPageEntryCommitClampsToOneWhenTotalPagesIsZero() {
        var page = 7
        let navigator = HwpPageNavigator(
            currentPage: Binding(get: { page }, set: { page = $0 }),
            totalPages: 0
        )

        navigator.commitPageEntry("3")

        expect(page) == 1
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

    /// 비-finite 바인딩은 쓰기 경로에서 트랩 없이 리셋 기본값으로 폴백해야 한다 —
    /// min/max 클램프는 NaN을 통과시킨다 (R57 #2). 표시 경로의 같은 방어는
    /// `testDisplayScaleGuardsAgainstConversionTraps`가 본다.
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
    }

    /// 표시는 `range`로 클램프하지 않는다 — `range`는 `±` 버튼의 이동 경계일 뿐
    /// 문서 뷰의 실제 배율 한계(`0.25...5.0`)를 구속할 통로가 없어, 표시까지
    /// 클램프하면 좁은 `range`를 넘긴 호스트에서 라벨이 실제와 다른 값을 말한다.
    /// 쓰기는 반대로 계속 클램프해야 `±` 버튼이 그 경계를 지킨다.
    @MainActor
    func testNarrowRangeDoesNotDistortDisplayedScale() {
        var zoomScale = CGFloat(0.25)
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
            range: 0.5 ... 2.0
        )

        expect(controls.displayScale(0.25)) == 0.25
        expect(controls.displayScale(5.0)) == 5.0
        expect(controls.displayPercent) == 25
        expect(controls.sanitized(0.25)) == 0.5
        controls.setZoomScale(0.25)
        expect(zoomScale) == 0.5
    }

    /// 표시 경로도 `Int(_ * 100)` 트랩을 막아야 한다 — 클램프를 뺀 자리에
    /// 비-finite 폴백과 표시 한계가 남는다.
    @MainActor
    func testDisplayScaleGuardsAgainstConversionTraps() {
        var zoomScale = CGFloat(1.0)
        let controls = HwpZoomControls(
            zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 })
        )

        expect(controls.displayScale(.nan)) == 1.0
        expect(controls.displayScale(.infinity)) == 1.0
        expect(controls.displayScale(-.infinity)) == 1.0
        expect(controls.displayScale(.greatestFiniteMagnitude)) == 10000
        expect(controls.displayScale(-.greatestFiniteMagnitude)) == -10000
        expect(controls.displayScale(2.0)) == 2.0

        controls.setZoomScale(.nan)
        expect(zoomScale) == 1.0
    }
}
