import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 비트맵 렌더러의 **자원·정의역 경계** (#76 리뷰).
///
/// 렌더 계약 자체는 `HwpPageBitmapRendererTests`가 본다. 여기가 잡는 것은 그
/// 바깥이다: 문서가 정하는 픽셀 수, 호스트가 넘기는 극단값, 그리고 CG가
/// **실패하지 않고 빈 그림을 성공으로 돌려주는** 입력들. 셋 다 정상 경로에서는
/// 보이지 않아 골든·해시가 영영 못 잡는다.
final class HwpPageBitmapRendererBoundsTests: XCTestCase {
    /// **문서가 픽셀 수를 정하는 경로의 가드.** 페이지 치수는 상한(14,400pt)만
    /// 클램프되고 하한은 `> 0`이라 1 HWPUNIT = 0.01pt 폭이 통과한다 — 그
    /// 종횡비(1,440,000)에 208px를 곱하면 299,520,000행 ≈ 249GB다. 화면 뷰는
    /// 페이지를 자연 크기로 그려 무사하므로 이 증폭은 폭을 끌어올리는 이 경로에만
    /// 있다.
    func testExtremePageAspectRatioIsBoundedInsteadOfExploding() async throws {
        let sliver = HwpPageBitmapRendererTests.makePage(
            commands: [], size: CGSize(width: 0.01, height: 14400)
        )

        let height = HwpPageBitmapRenderer.pixelHeight(for: sliver, pixelWidth: 208)
        expect(height) == HwpPageBitmapRenderer.maximumPixelDimension

        // 상한 안이므로 **거부가 아니라 렌더**다 — 축소판은 보조 표시라 눌린
        // 그림이 쪽을 통째로 잃는 것보다 낫다.
        let image = try await HwpPageBitmapRenderer.render(
            page: sliver, imageStore: HwpImageStore(), pixelWidth: 208, pixelHeight: height
        )
        expect(image.width) == 208
        expect(image.height) == HwpPageBitmapRenderer.maximumPixelDimension
    }

    /// 픽셀 폭은 공개 인자라 `Int.max`가 들어온다. 크기 헬퍼는 **클램프**해
    /// 호스트가 셀 자리를 잡게 하고 렌더러는 **거부**하되, 어느 쪽도
    /// `Int(CGFloat)`·`pixelWidth * 4`에서 트랩하면 안 된다.
    func testExtremePixelWidthIsRejectedInsteadOfTrapping() async {
        let page = HwpPageBitmapRendererTests.makePage(commands: [])
        let degenerate = HwpPageBitmapRendererTests.makePage(commands: [], size: .zero)

        expect(HwpPageBitmapRenderer.pixelHeight(for: page, pixelWidth: .max))
            == HwpPageBitmapRenderer.maximumPixelDimension
        expect(HwpPageBitmapRenderer.pixelHeight(for: degenerate, pixelWidth: .max))
            == HwpPageBitmapRenderer.maximumPixelDimension

        await expect {
            try await HwpPageBitmapRenderer.render(
                page: page, imageStore: HwpImageStore(), pixelWidth: .max, pixelHeight: 10
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case .invalidPixelSize = error else {
                return fail("Expected .invalidPixelSize, got \(error)")
            }
        })
    }

    /// **축별 상한만으로는 모자란다.** 두 축을 다 요구하는 극단이 아니라 **폭
    /// 하나짜리 요청**이 1 GiB로 간다 — 세로 페이지에서는 높이가 상한까지
    /// 클램프되기 때문이고, `maximumPixelDimension`이 공개 상수라 그 값을 그대로
    /// 넘기는 것이 자연스러운 사용이다.
    func testTotalPixelAreaIsCappedBelowThePerAxisSquare() async {
        let portrait = HwpPageBitmapRendererTests.makePage(
            commands: [], size: CGSize(width: 595, height: 842)
        )
        let cap = HwpPageBitmapRenderer.maximumPixelDimension

        // 폭만 상한으로 줘도 높이가 상한까지 올라온다 (자연 높이 23,185 → 클램프)
        expect(HwpPageBitmapRenderer.pixelHeight(for: portrait, pixelWidth: cap)) == cap

        await expect {
            try await HwpPageBitmapRenderer.render(
                page: portrait, imageStore: HwpImageStore(),
                pixelWidth: cap, pixelHeight: cap
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case .invalidPixelSize = error else {
                return fail("Expected .invalidPixelSize, got \(error)")
            }
        })

        // 경계 대조군 — 상한과 **정확히 같은** 면적은 통과한다. 검증만 부르므로
        // 64 MiB를 실제로 할당하지는 않는다.
        let side = 4096
        expect(side * side) == HwpPageBitmapRenderer.maximumPixelCount
        expect {
            try HwpPageBitmapRenderer.validatedGeometry(
                page: portrait, pixelWidth: side, pixelHeight: side, sourceRect: nil
            )
        }.toNot(throwError())
    }

    /// 값싼 검증이 **디코드보다 먼저**여야 한다. 예산이 빠듯한 `.fail` 경로에서
    /// 순서가 뒤집히면 `.unresolvedImages`가 먼저 나와, 잘못된 입력을 알려 주려고
    /// 만든 오류가 엉뚱한 것으로 바뀐다 — 그것도 예산을 다 쓴 뒤에.
    func testInvalidRequestFailsBeforeDecodingPageImages() async throws {
        let document = try HwpPageBitmapRendererTests.makeImageDocument(imageCount: 3)
        let page = try XCTUnwrap(document.pages.first)

        // 같은 문서·같은 예산이 **유효한** 크기에서는 `.unresolvedImages`를 낸다
        // (`testUnresolvedPolicyDecidesBetweenPlaceholderAndFailure`). 그러므로
        // 아래가 입력 오류라는 것은 디코드 전에 끝났다는 뜻이다.
        await expect {
            try await HwpPageBitmapRenderer.render(
                page: page, imageStore: document.imageStore,
                pixelWidth: .max, pixelHeight: 80,
                unresolvedImages: .fail, imageByteLimit: 1
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case .invalidPixelSize = error else {
                return fail("Expected .invalidPixelSize, got \(error)")
            }
        })

        await expect {
            try await HwpPageBitmapRenderer.render(
                page: page, imageStore: document.imageStore,
                pixelWidth: 60, pixelHeight: 80,
                sourceRect: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                unresolvedImages: .fail, imageByteLimit: 1
            )
        }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
            guard case .invalidSourceRect = error else {
                return fail("Expected .invalidSourceRect, got \(error)")
            }
        })
    }

    /// **CG는 이 입력들에서 실패하지 않는다** — NaN 원점·무한 크기·비정규 크기
    /// 모두 `makeImage()`가 성공하고 아무것도 그려지지 않은 흰 비트맵이 나온다
    /// (실측). `width/height > 0` 하나로는 셋 다 통과하므로, 검사가 없으면 빈
    /// 그림이 `.fail` 정책 경로(픽스처 기준선·PDF)에서 정답으로 굳는다.
    func testNonFiniteSourceRectIsRejected() async {
        let page = HwpPageBitmapRendererTests.makePage(commands: [])
        // `.infinity`/`.nan`을 리터럴로 쓰면 CGFloat·Double 오버로드가 모호해진다.
        let nan = CGFloat.nan
        let inf = CGFloat.infinity
        let subnormal = CGFloat.leastNonzeroMagnitude
        let rects: [CGRect] = [
            CGRect(x: nan, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: nan, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: inf, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: inf),
            CGRect(x: 0, y: 0, width: subnormal, height: 100),
            CGRect(x: 0, y: 0, width: nan, height: 100),
        ]

        for rect in rects {
            await expect {
                try await HwpPageBitmapRenderer.render(
                    page: page, imageStore: HwpImageStore(),
                    pixelWidth: 60, pixelHeight: 80, sourceRect: rect
                )
            }.to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
                guard case .invalidSourceRect = error else {
                    return fail("Expected .invalidSourceRect for \(rect), got \(error)")
                }
            })
        }
    }
}
