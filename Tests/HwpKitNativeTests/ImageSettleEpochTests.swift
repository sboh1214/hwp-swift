import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 변형별 확정 에포크 — `resolveImage`의 축출 라이브락 컷이 기대는 신호.
///
/// 요청과 대기자 등록 **사이**에 확정이 지나가고 그 결과가 다른 변형의 삽입에
/// 축출되면, 등록 측엔 캐시에도 추적에도 흔적이 없어 확정을 못 본 것으로 오인한다.
/// 그러면 `didSettleOnce`가 서지 않아 해석자들이 서로를 밀어내며 끝나지 않는다.
///
/// 그 인터리빙 자체는 `requestImage`와 등록 사이에 끼어들 이음매가 없어 결정론적
/// 재현이 불가능하다. 대신 컷이 기대는 **성질**을 여기서 잠근다.
final class ImageSettleEpochTests: XCTestCase {
    private func makeCGImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func variant(_ index: Int) -> String {
        HwpPageImageProvider.variantKey(1, HwpImageRenderStyle(cropLeft: Int32(index)))
    }

    private func makeStore() throws -> HwpImageStore {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination)) == true
        return HwpImageStore(
            dataByBinItemId: [1: data as Data], extensionByBinItemId: [1: "png"]
        )
    }

    /// 확정은 에포크를 올리고, 그 뒤 **예산 축출로 캐시에서 사라져도** 그 사실이
    /// 남아야 한다 — 축출된 변형은 `resolved`에도 `failedKeys`에도 없어서, 이
    /// 값만이 "이미 한 번 확정됐다"를 증언한다.
    func testSettlementAdvancesEpochAndSurvivesEviction() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        let image = try makeCGImage()
        expect(provider.settleEpochSnapshot(self.variant(1))) == 0

        provider.finishRequest(
            key: 1, variant: variant(1), generation: 0, image: image, cost: 10
        )
        expect(provider.settleEpochSnapshot(self.variant(1))) == 1

        // 예산을 조여 다른 변형의 삽입이 1을 축출하게 한다
        provider.resolvedByteLimit = 10
        provider.finishRequest(
            key: 1, variant: variant(2), generation: 0, image: image, cost: 10
        )

        expect(provider.cachedImage(for: 1, style: HwpImageRenderStyle(cropLeft: 1))).to(beNil())
        expect(provider.settleEpochSnapshot(self.variant(1))) == 1
    }

    /// 디코드 실패도 확정이다 — `failedKeys`에 남으므로 재시도 대상이 아니다.
    func testRecordedFailureAdvancesEpoch() {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())

        provider.finishRequest(
            key: 1, variant: variant(1), generation: 0, image: nil, cost: 0
        )

        expect(provider.didFail(for: 1, style: HwpImageRenderStyle(cropLeft: 1))) == true
        expect(provider.settleEpochSnapshot(self.variant(1))) == 1
    }

    /// 캐시 purge에 취소된 요청은 확정이 **아니다** (R67 — 재시도 대상). 여기서
    /// 에포크가 올라가면 그 재시도 경로가 축출로 오분류돼 회색 사각형이 남는다.
    func testPurgeCancelledRequestDoesNotAdvanceEpoch() {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())

        provider.finishRequest(
            key: 1, variant: variant(1), generation: 0,
            image: nil, cost: 0, recordsFailure: false
        )

        expect(provider.didFail(for: 1, style: HwpImageRenderStyle(cropLeft: 1))) == false
        expect(provider.settleEpochSnapshot(self.variant(1))) == 0
    }

    /// 해석 **시작 전에** 확정·축출된 변형은 그대로 다시 디코드해야 한다. 에포크
    /// 스냅샷은 호출 안에서 뜨므로 과거 확정이 `.settled`로 오인되지 않는다 —
    /// 이 구분이 없으면 페이지가 바뀔 때 공유 이미지가 회색으로 남는다.
    func testResolveStillDecodesVariantEvictedBeforeItStarted() async throws {
        let provider = HwpPageImageProvider(store: try makeStore(), cache: HwpImageCache())
        let filler = try makeCGImage()
        let target = HwpPageImageProvider.variantKey(1, nil)
        provider.finishRequest(
            key: 1, variant: target, generation: 0, image: filler, cost: 10
        )
        provider.resolvedByteLimit = 10
        provider.finishRequest(
            key: 1, variant: variant(9), generation: 0, image: filler, cost: 10
        )
        expect(provider.cachedImage(for: 1)).to(beNil())
        expect(provider.settleEpochSnapshot(target)) == 1

        let image = await provider.resolveImage(for: 1)

        expect(image).toNot(beNil())
    }

    /// 대기자 등록은 다른 태스크에서 일어나므로 관측 시점을 맞춘다.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                fail("조건이 \(timeout)초 안에 만족되지 않았다")
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// 해석이 도는 동안에는 고정 집합이 바뀌어도 그 변형의 확정 이력을 지우면
    /// 안 된다. 지우면 조회 기본값이 0이라 스냅샷이 0이던 첫 해석에서 비교가
    /// 같아져, 확정이 없던 것처럼 보이고 등록 경합 컷이 다시 뚫린다. 뷰가
    /// 스크롤로 `setPinnedImages`를 부르는 동안 오프스크린 해석자가 도는
    /// 상황(공유 provider)이 그 형상이다.
    func testPruneKeepsEpochWhileResolverIsActive() async throws {
        let provider = HwpPageImageProvider(store: try makeStore(), cache: HwpImageCache())
        let target = HwpPageImageProvider.variantKey(1, nil)
        let filler = try makeCGImage()
        provider.finishRequest(key: 1, variant: target, generation: 0, image: filler, cost: 10)
        provider.resolvedByteLimit = 10
        provider.finishRequest(key: 1, variant: variant(9), generation: 0, image: filler, cost: 10)
        expect(provider.cachedImage(for: 1)).to(beNil())
        expect(provider.settleEpochSnapshot(target)) == 1

        // 진행 슬롯 0 = 확정이 발생하지 않아 해석자가 대기 상태로 서 있는다
        provider.maximumInFlight = 0
        let pending = Task { await provider.resolveImage(for: 1) }
        try await waitUntil { provider.settleWaiterCount(target) == 1 }

        // 뷰 스크롤이 가시 집합을 바꾼 상황 — 이 변형은 고정에서 빠진다
        provider.setPinnedImages([])
        expect(provider.settleEpochSnapshot(target)) == 1

        provider.maximumInFlight = 4
        provider.finishRequest(key: 1, variant: target, generation: 0, image: filler, cost: 10)
        let resolved = await pending.value
        expect(resolved).toNot(beNil())
        // 해석이 끝나면 보호도 끝난다 — 무기한이면 상한이 무력해진다
        expect(provider.settleEpochSnapshot(target)) == 0
    }

    /// 에포크는 고정 집합 밖에서 값이 없다 — 함께 줄이지 않으면 예산 축출된
    /// 변형이 어디에서도 정리되지 않고 문서 전체 변형 수만큼 쌓인다.
    func testEpochsArePrunedToPinnedSet() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        let image = try makeCGImage()
        for index in 1 ... 3 {
            provider.finishRequest(
                key: 1, variant: variant(index), generation: 0, image: image, cost: 10
            )
        }

        provider.setPinnedImages([variant(2)])

        expect(provider.settleEpochSnapshot(self.variant(1))) == 0
        expect(provider.settleEpochSnapshot(self.variant(2))) == 1
        expect(provider.settleEpochSnapshot(self.variant(3))) == 0
    }
}
