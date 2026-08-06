import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 페이지 단위 캐시 정리(`retainOnlyImages`)의 계약과 선형성.
///
/// 이전 형태는 축출마다 `firstIndex` + `remove(at:)`을 불러 스캔·이동이 각각
/// O(N)이라 이차였다. 변형 키가 (binItemId, 자르기·밝기·명암·효과)라 한 페이지가
/// 같은 그림의 crop 인스턴스를 수천 개 참조하면 닿는 크기다.
///
/// baseline (2026-08-06 로컬 릴리스, 한 패스 전, 변형 N개 중 앞 절반 고정):
/// N=4,000 203ms · 8,000 874ms · 16,000 3,611ms — 배가 될 때마다 4배.
final class ImagePruningTests: XCTestCase {
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

    /// crop만 다른 변형 키 — 한 그림이 여러 변형으로 갈리는 실제 형상이다.
    private func variant(_ index: Int) -> String {
        HwpPageImageProvider.variantKey(1, HwpImageRenderStyle(cropLeft: Int32(index)))
    }

    @discardableResult
    private func fill(_ provider: HwpPageImageProvider, count: Int, cost: Int) throws -> [String] {
        let image = try makeCGImage()
        return (0 ..< count).map { index in
            let key = variant(index)
            provider.finishRequest(
                key: 1, variant: key, generation: 0, image: image, cost: cost
            )
            return key
        }
    }

    /// 버린 변형의 바이트가 실제로 빠져야 한다. 압축을 마지막에 한 번만 하면서
    /// 비용 차감을 놓치면 예산이 영구히 부풀어, 남긴 변형이 곧바로 축출된다.
    func testRetainOnlyImagesReleasesDroppedBytes() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        provider.resolvedByteLimit = 30
        let keys = try fill(provider, count: 3, cost: 10)

        provider.retainOnlyImages([keys[2]])
        // 남은 몫이 10이어야 20을 더 넣어도 예산(30) 안이다
        provider.finishRequest(
            key: 1, variant: variant(90), generation: 0, image: try makeCGImage(), cost: 10
        )
        provider.finishRequest(
            key: 1, variant: variant(91), generation: 0, image: try makeCGImage(), cost: 10
        )

        expect(provider.cachedImage(for: 1, style: HwpImageRenderStyle(cropLeft: 2))).toNot(beNil())
    }

    /// 압축이 보유 순서를 지켜야 한다 — 뒤집히면 예산 초과 시 가장 최근 변형이
    /// 먼저 축출된다 (LRU가 MRU가 된다).
    func testRetainOnlyImagesPreservesEvictionOrder() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        let keys = try fill(provider, count: 4, cost: 10)

        // 남기는 둘은 삽입 순서상 0 → 2 이고, 그 순서가 축출 우선순위가 된다
        provider.retainOnlyImages([keys[0], keys[2]])
        provider.resolvedByteLimit = 20
        provider.setPinnedImages([])
        provider.finishRequest(
            key: 1, variant: variant(92), generation: 0, image: try makeCGImage(), cost: 10
        )

        expect(provider.cachedImage(for: 1, style: HwpImageRenderStyle(cropLeft: 0))).to(beNil())
        expect(provider.cachedImage(for: 1, style: HwpImageRenderStyle(cropLeft: 2))).toNot(beNil())
    }

    /// 기본 (CI): N=4,000 스모크 + 폭주 방지 상한만. `HWP_PERF=1`: N=16,000 실측.
    func testPruningStaysLinear() throws {
        let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
        let count = full ? 16000 : 4000
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        let keys = try fill(provider, count: count, cost: 16)
        // 앞 절반을 남긴다 — 이전 형태의 최악 경우다 (매 축출이 고정 접두를 훑는다)
        let pinned = Set(keys.prefix(count / 2))

        let clock = ContinuousClock()
        let start = clock.now
        provider.retainOnlyImages(pinned)
        let elapsed = clock.now - start

        expect(provider.cachedImage(for: 1, style: HwpImageRenderStyle(cropLeft: 0)))
            .toNot(beNil())
        expect(provider.cachedImage(
            for: 1, style: HwpImageRenderStyle(cropLeft: Int32(count - 1))
        )).to(beNil())
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("HWP_PERF pruning: N=\(count) time=\(String(format: "%.3f", seconds))s")
        // 임계 = 한 패스 실측 + 넉넉한 여유. 이차로 되돌아가면 이 값을 넘는다.
        expect(seconds) < (full ? 1.0 : 0.5)
    }
}
