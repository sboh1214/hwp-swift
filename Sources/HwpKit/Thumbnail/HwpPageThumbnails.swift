import CoreGraphics
import Foundation
import HwpKitCore
import HwpKitNative

public enum HwpThumbnailError: Error, Sendable {
    case cancelled
    case pageOutOfRange(index: Int, pageCount: Int)
    case renderFailed(String)
}

extension HwpThumbnailError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled:
            "Thumbnail rendering was cancelled"
        case let .pageOutOfRange(index, pageCount):
            "Page \(index + 1) is outside the document (\(pageCount) page(s))"
        case let .renderFailed(reason):
            "Thumbnail rendering failed: \(reason)"
        }
    }
}

extension HwpThumbnailError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// 문서의 쪽 축소판을 만들어 들고 있는 렌더러 — 썸네일 사이드바·Quick Look
/// 미리보기·문서 목록 카드가 같은 자리에서 나온다.
///
/// 화면 렌더와 **같은 paint list·같은 조판**을 쓴다 (`HwpPageLayer.draw(in:)`가
/// 뷰 계층 없이 임의 `CGContext`에 그리는 순수 오프스크린 렌더러라 가능하다 —
/// 구현은 HwpKitNative의 `HwpPageThumbnailRenderer`). `HwpPDFExporter`와 같은
/// 관계다.
///
/// PDF 내보내기와 갈리는 지점이 둘 있다:
///
/// - **미완성 문서를 거부하지 않는다.** 프로그레시브 로딩의 중간 스냅샷도 그대로
///   받아 지금까지 확정된 쪽을 그린다 — 축소판은 사용자가 보관하는 산출물이
///   아니라 진행 중인 문서를 훑는 수단이라, 쪽이 늘어나면 목록이 함께 자라는 것이
///   맞다. `update(document:)`가 그 증분을 알아본다.
/// - **미확정 이미지를 실패로 보지 않는다.** 바이트 예산에 걸린 그림은 회색
///   플레이스홀더로 남긴다 — 그림 하나 때문에 쪽 전체를 잃는 것이 더 나쁘다.
///
/// UI는 넘기지 않는다: 목록·그리드 레이아웃은 호스트 몫이고
/// `Sample/HwpSwiftSample/ThumbnailSidebar.swift`가 배선 예를 보인다
/// (개요 사이드바와 같은 기준).
public final class HwpPageThumbnails: @unchecked Sendable {
    private let renderer: HwpPageThumbnailRenderer

    /// - Parameters:
    ///   - imageByteLimit: 그림 디코드 예산. 변형 예산과 원본 캐시 예산에 **함께**
    ///     걸린다 — 한쪽만 낮추면 상한이 두 배가 된다.
    ///   - thumbnailCacheBytes: 렌더된 축소판 보유 예산 (삽입순 결정적 축출).
    public init(
        imageByteLimit: Int = HwpPageBitmapRenderer.defaultImageByteLimit,
        thumbnailCacheBytes: Int = HwpPageThumbnails.defaultCacheBytes
    ) {
        renderer = HwpPageThumbnailRenderer(
            imageByteLimit: imageByteLimit,
            thumbnailCacheBytes: thumbnailCacheBytes
        )
    }

    public static let defaultCacheBytes = HwpPageThumbnailRenderer.defaultThumbnailCacheBytes

    /// 지금 대상 문서의 쪽 수.
    public var pageCount: Int {
        renderer.pageCount
    }

    /// 대상 문서를 갈아 끼운다. 프로그레시브 스냅샷(같은 로드의 다음 배치)이면
    /// 이미 그린 축소판과 디코드된 그림을 유지하고 쪽 수만 늘린다 — 스냅샷마다
    /// 불러도 1,030쪽 문서가 처음부터 다시 그려지지 않는다.
    public func update(document: HwpDocument) {
        renderer.update(document: document)
    }

    /// 0-기반 쪽 인덱스의 축소판.
    ///
    /// `HwpPageNavigator`·`HwpOutlineItem.pageNumber`는 **1-기반**이므로 그쪽에서
    /// 넘어온 값은 `- 1`을 해서 넣는다 (`HwpOutlineItem.pageIndex`가 이미 변환된
    /// 값이다).
    ///
    /// 요청은 직렬화된다 — 여러 셀이 동시에 불러도 한 번에 한 쪽씩 그리고, 이미
    /// 그린 쪽은 같은 인스턴스로 즉시 돌려준다.
    ///
    /// 호출 태스크를 취소하면 (SwiftUI `.task`가 셀이 사라질 때 하듯) **대기가
    /// 끊기고** `.cancelled`가 난다 — 그 쪽을 위해 더 요청하지 않으므로 남은
    /// 디코드는 시작되지 않는다. 다만 **이미 스폰된 디코드는 그대로 돈다**:
    /// 공급자가 그것을 비구조적 태스크로 들고 있어 호출자 취소가 닿지 않는다.
    /// 그것까지 즉시 놓으려면 `cancelOutstanding()`이다.
    public func image(forPageAt index: Int, pixelWidth: Int) async throws -> CGImage {
        do {
            return try await renderer.image(forPageAt: index, pixelWidth: pixelWidth)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// 페이지 종횡비를 유지하는 픽셀 높이 — 셀 자리를 미리 잡을 때 쓴다.
    public static func pixelHeight(for page: HwpPage, pixelWidth: Int) -> Int {
        HwpPageBitmapRenderer.pixelHeight(for: page, pixelWidth: pixelWidth)
    }

    /// 진행 중인 그림 디코드를 끊는다 (사이드바를 닫을 때). 이미 만든 축소판은
    /// 남는다 — 다시 열 때 재렌더할 이유가 없다.
    public func cancelOutstanding() {
        renderer.cancelOutstanding()
    }

    private static func mapped(_ error: Error) -> HwpThumbnailError {
        if error is CancellationError {
            return .cancelled
        }
        // 범위 밖 쪽은 재시도 가능한 상태다 — 프로그레시브 로딩 중에는 그 쪽이
        // 아직 안 왔을 뿐이라, 문자열로 접으면 호스트가 진짜 실패와 못 가른다.
        if let renderError = error as? HwpPageBitmapRenderError,
           case let .pageOutOfRange(index, pageCount) = renderError
        {
            return .pageOutOfRange(index: index, pageCount: pageCount)
        }
        return .renderFailed(error.localizedDescription)
    }
}
