import SwiftUI

/// 문서를 열기 전 화면 (#126) — **호스트가 만드는 UI의 예시**다.
///
/// 라이브러리 표면을 하나도 쓰지 않는 화면이라 `ContentView`에서 갈라 두었다
/// (#140). 상태는 하나도 들지 않는다 — 최근 문서 목록의 진실 원본은
/// `RecentDocumentsStore`(defaults)이고 그 거울을 드는 것은 호스트다. 여기서
/// `@State`로 다시 들면 다른 창이 기록·제거한 항목이 이 화면에 반영되지 않는다
/// (`ContentView`가 `UserDefaults.didChangeNotification`으로 그 거울을 맞춘다).
struct EmptyState: View {
    /// 로드 실패 사유. 문서를 보는 중에는 이 화면이 없으므로 여기서만 보인다.
    let errorMessage: String?
    /// 최근 문서 목록 — 비어 있으면 목록 자체가 나타나지 않는다.
    let recents: [RecentDocument]
    /// 열기 버튼(또는 Return)을 눌렀을 때.
    let onOpen: () -> Void
    /// 최근 문서 행을 눌렀을 때. 열 수 없는 항목을 목록에서 거두는 것도
    /// 호스트 몫이다 — 이 화면은 눌렸다는 사실만 전한다.
    let onSelectRecent: (RecentDocument) -> Void
    /// 컨텍스트 메뉴의 "목록에서 제거".
    let onRemoveRecent: (RecentDocument) -> Void

    /// 스크롤로 감싸는 이유: 최근 문서가 10개까지 쌓이면 내용이 낮은 뷰포트
    /// (iPhone 가로 모드)를 넘는데, 스크롤이 없으면 넘친 행을 눌러서 열 방법이
    /// 없다. 내용이 짧을 때는 `minHeight`가 뷰포트를 채워 종전처럼 중앙 정렬된다.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Open a .hwp or .hwpx file to preview")
                        .foregroundStyle(.secondary)
                    Button("Open .hwp / .hwpx") { onOpen() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Text("또는 .hwp/.hwpx 파일을 여기로 끌어다 놓기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if !recents.isEmpty {
                        recentDocumentsList
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    /// 빈 상태 아래에 붙는 최근 문서 목록 (#126). 픽스처가 전부
    /// `document.hwp`/`document.hwpx`라 이름만으로는 구별되지 않아 폴더를
    /// 보조 행으로 함께 보인다.
    private var recentDocumentsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 문서")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(recents) { item in
                Button {
                    onSelectRecent(item)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.folderDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("목록에서 제거", role: .destructive) {
                        onRemoveRecent(item)
                    }
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}
