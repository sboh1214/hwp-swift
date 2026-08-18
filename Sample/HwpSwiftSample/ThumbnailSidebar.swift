import CoreGraphics
import HwpKit
import HwpKitCore
import SwiftUI

/// 페이지 축소판 사이드바 (#76) — **호스트가 만드는 UI의 예시**다.
///
/// `HwpKit`은 목록·그리드 UI를 내지 않는다 (`Sources/HwpKit/AGENTS.md`의 "v1
/// 스코프 밖" — 개요 목록과 같은 기준). 대신 `HwpPageThumbnails`가 쪽 → 비트맵을
/// 책임지므로, 이 파일은 그 재료만으로 사이드바가 만들어짐을 보인다.
///
/// `OutlineSidebar`와 코드를 공유하지 않는다: 그쪽은 `List` 한 줄이면 되지만
/// 여기는 `LazyVGrid` + **셀별 지연 요청·취소**가 필요하다. 지연이 요점이다 —
/// 1,030쪽 문서에서 전부 그리면 수 분이 걸린다.
struct ThumbnailSidebar: View {
    let document: HwpDocument
    /// **1-기반**이다 (`HwpPageNavigator`·`OutlineSidebar`와 같은 규약).
    /// 배열 인덱스는 0-기반이므로 두 축의 `+1`/`-1` 변환을 이 파일이 명시한다.
    @Binding var currentPage: Int
    /// 호스트가 소유한다 — 사이드바를 여닫거나 iPhone 시트를 다시 띄울 때마다
    /// 새로 만들면 그때까지 그린 축소판을 통째로 버린다.
    let thumbnails: HwpPageThumbnails
    /// 항목을 눌러 이동한 **뒤** 호스트가 할 일 (iPhone 시트 닫기 등).
    var onSelect: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: ThumbnailMetrics.cellWidth), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(document.pages.enumerated()), id: \.offset) { index, page in
                        ThumbnailCell(
                            pageIndex: index,
                            pageSize: page.size,
                            isCurrent: index + 1 == currentPage,
                            thumbnails: thumbnails
                        ) {
                            // 배열은 0-기반, 바인딩은 1-기반이다.
                            currentPage = index + 1
                            onSelect?()
                        }
                        .id(index)
                    }
                }
                .padding(12)
            }
            // 처음 열 때도 현재 쪽으로 데려온다. `onChange`는 **이후** 변화에만
            // 발화하므로 이것이 없으면 500쪽을 보다 사이드바를 열어도 그리드가
            // 1쪽에서 시작한다 — 지나가는 셀마다 렌더 요청이 직렬 게이트에
            // 쌓이므로 손으로 스크롤해 찾는 대가가 특히 크다.
            .task {
                // 레이아웃이 **한 번 돌고 난 뒤에야** `scrollTo`가 대상 자리를
                // 찾는다 — 그 전에는 `LazyVGrid`가 화면 밖 셀을 아직 만들지 않아
                // 호출이 조용히 무시된다 (시뮬레이터 실측: `onAppear`에서 바로
                // 부르거나 `Task {}` 한 홉만 태우면 26쪽에서 열어도 1쪽에서
                // 시작한다). 한 프레임 몫만 기다렸다 부른다.
                try? await Task.sleep(for: .milliseconds(100))
                proxy.scrollTo(currentPage - 1, anchor: .center)
            }
            .onChange(of: currentPage) { _, page in
                // 뷰를 스크롤해 쪽이 바뀌면 그 축소판을 화면 안으로 데려온다 —
                // 1,030쪽 목록에서는 이것이 없으면 현재 위치를 영영 못 찾는다.
                withAnimation { proxy.scrollTo(page - 1, anchor: .center) }
            }
        }
        // 사이드바를 닫으면 진행 중인 디코드를 놓는다 — 셀의 `.task` 취소가
        // 이미 대부분을 끊지만, 게이트를 통과해 디코드 중인 쪽 하나는 그쪽 태스크가
        // 사라져도 계속 돌 수 있다.
        //
        // `update(document:)`는 여기서 부르지 않는다. 렌더러를 호스트가 소유하므로
        // 갱신도 호스트 몫이다 (`ContentView`가 스냅샷마다 부른다) — 양쪽에서
        // 부르면 loadToken이 없는 문서에서 서로를 전체 교체로 판정해 그때까지 그린
        // 축소판을 버린다.
        .onDisappear { thumbnails.cancelOutstanding() }
    }
}

/// 사이드바와 셀이 함께 쓰는 치수. 두 곳에 흩어 두면 셀 폭과 요청 픽셀 폭이
/// 따로 움직여 축소판이 흐려지거나 과하게 커진다.
private enum ThumbnailMetrics {
    /// 셀 폭 (pt). 260pt 열에 두 칸이 들어간다.
    static let cellWidth: CGFloat = 104
    /// 요청 픽셀 폭 — Retina에서 확대돼 흐려지지 않게 2배로 뜬다.
    static let pixelWidth = Int(cellWidth * 2)
}

/// 축소판 한 칸. `.task`가 셀 등장 시 요청을 걸고 사라질 때 취소하므로,
/// `LazyVGrid`가 화면 밖 셀을 걷어 가면 그 디코드도 함께 끊긴다 — 스로틀
/// 슬롯(전역 3개)을 가시 페이지와 나눠 쓰는 구조라 이 취소가 중요하다.
private struct ThumbnailCell: View {
    let pageIndex: Int
    let pageSize: CGSize
    let isCurrent: Bool
    let thumbnails: HwpPageThumbnails
    let onSelect: () -> Void

    @State private var image: CGImage?
    @State private var failed = false

    /// 자리를 **미리** 잡는다. 비어 있는 동안 높이가 0이면 그리드가 재배치되면서
    /// 셀이 화면 안팎을 오가 요청·취소가 반복된다.
    private var cellHeight: CGFloat {
        let width = ThumbnailMetrics.cellWidth
        guard pageSize.width > 0, pageSize.height > 0 else { return width }
        return (width * pageSize.height / pageSize.width).rounded()
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                page
                    .frame(width: ThumbnailMetrics.cellWidth, height: cellHeight)
                    .overlay(
                        Rectangle()
                            .stroke(
                                isCurrent ? Color.accentColor : Color.secondary.opacity(0.4),
                                lineWidth: isCurrent ? 2 : 1
                            )
                    )
                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await load() }
        .accessibilityLabel("\(pageIndex + 1)쪽 축소판")
        .accessibilityHint("\(pageIndex + 1)쪽으로 이동")
    }

    @ViewBuilder
    private var page: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Rectangle().fill(Color.white)
                if failed {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func load() async {
        guard image == nil else { return }
        do {
            image = try await thumbnails.image(
                forPageAt: pageIndex, pixelWidth: ThumbnailMetrics.pixelWidth
            )
            failed = false
        } catch HwpThumbnailError.cancelled {
            // 셀이 화면 밖으로 나갔다 — 다시 나타나면 `.task`가 다시 요청한다.
        } catch {
            // 로딩 중 문서에는 아직 없는 쪽일 수 있다 (`.pageOutOfRange`). 다음
            // 스냅샷이 그 쪽을 데려오면 그리드가 셀을 다시 만들어 재요청된다.
            failed = true
        }
    }
}
