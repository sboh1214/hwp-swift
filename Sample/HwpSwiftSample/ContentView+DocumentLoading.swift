import HwpKit
import HwpKitCore
import SwiftUI

/// 문서를 여는 경로 넷 (#6·#126) — `fileImporter`·`onOpenURL`·드래그앤드롭·
/// 최근 문서가 전부 `loadDocument(from:)`으로 모인다.
///
/// 관측 가능한 모델 타입으로 뽑지 않고 `ContentView`의 extension으로 나눈
/// 이유 (#140): 이 경로의 정확성이 **두 세대 카운터**에 걸려 있다.
/// `loadGeneration`은 진행 중인 로드가 자기 UI 적용분만 쓰도록 지역 변수로
/// 값을 캡처해 현재 값과 비교하고, `openGeneration`은 느리게 도착한 드롭
/// 완료가 그 사이 열린 문서를 덮지 못하게 한다 — 후자를 올리는 곳이
/// `handleDrop`·`loadDocument`·`cancelExportOnTeardown` 셋이라, 어느 하나가
/// 다른 타입으로 떨어져 나가면 나머지가 같은 카운터를 못 올려 #126이 고친
/// 버그가 그대로 되살아난다. extension은 `@State` 소유권을 건드리지 않는다.
extension ContentView {
    /// 드롭된 provider에서 URL을 뽑아 연다 (#126). 확장자 검증 실패 등의
    /// 사유는 `errorMessage`로 올린다 — 문서를 보는 중에는 그 라벨이 화면에
    /// 없지만, 그때는 열려 있는 문서가 그대로라 조용히 무시되는 것이 맞다.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // 세대를 **먼저** 올려 두는 것은 완료가 동기로 오는 경우까지 덮기
        // 위해서다. 드롭이 거절되면(후보 없음) 완료는 오지 않으므로 되돌린다 —
        // 안 되돌리면 폴더처럼 열 수 없는 것을 떨어뜨린 것만으로 진행 중이던
        // 드롭이 취소된다.
        let previous = openGeneration
        openGeneration += 1
        let generation = openGeneration
        let request = DropOpenSupport.open(providers: providers) { result in
            // 이 요청이 시작된 뒤 다른 열기가 있었으면 결과를 버린다 — 성공만이
            // 아니라 실패도 버려야 낡은 사유가 새 문서 위에 오류로 남지 않는다.
            guard generation == openGeneration else {
                // 버리는 성공 값이 소유 사본이면 이 참조가 마지막이다 — 원본은
                // 출처 플래그가 걸러 이 삭제에 닿지 않는다.
                if case let .success(opened) = result, opened.isOwnedCopy {
                    DropOpenSupport.discardCopy(at: opened.url)
                }
                return
            }
            switch result {
            case let .success(opened):
                loadDocument(from: opened.url, isOwnedDropCopy: opened.isOwnedCopy)
            case let .failure(failure):
                errorMessage = failure.message
            }
        }
        // 이전 전송을 끊는 것도 **수락됐을 때만**이다 — 거절(후보 없음)이 진행
        // 중이던 드롭을 죽이면 안 되는 것은 세대 되감기와 같은 이유다.
        guard let request else {
            openGeneration = previous
            return false
        }
        dropRequest?.cancel()
        dropRequest = request
        return true
    }

    /// 최근 항목을 연다. 열 수 없는 항목은 그 자리에서 거둔다 — 눌러도 아무 일이
    /// 없는 시체 행을 남기지 않는다.
    func openRecent(_ item: RecentDocument) {
        switch RecentDocumentsStore.resolve(item) {
        case let .resolved(url):
            loadDocument(from: url)
        case .inaccessible:
            recents = RecentDocumentsStore.remove(item)
            errorMessage = "\(item.name)을(를) 열 권한이 없어 목록에서 제거했습니다. 다시 선택해 주세요."
        case .unavailable:
            recents = RecentDocumentsStore.remove(item)
            errorMessage = "\(item.name)을(를) 찾을 수 없어 최근 문서에서 제거했습니다."
        }
    }

    func loadDocument(from url: URL, isOwnedDropCopy: Bool = false) {
        // 이전 로드를 취소해 겹치는 파싱·첫 페이지 레이아웃이 동시에 자원을
        // 소모하지 않게 한다 (#6). 스트림 취소는 actor의 파싱까지 전파된다.
        loadTask?.cancel()
        errorMessage = nil
        document = nil
        // 요소 목록의 내용은 문서 교체가 알아서 갈지만, 표시 여부는 상태라
        // 직접 접는다 — 새 문서를 열자마자 옛 문서의 진단 열이 떠 있지 않게 (#126).
        showUnsupportedList = false
        // 새 로드가 첫 스냅샷을 내기 전에 실패하면 이 렌더러를 갱신할 주체가 없어
        // 옛 문서(쪽·공급자·디코드 이미지·축소판)가 오류 화면 내내 상주한다.
        // `cancelOutstanding()`은 요청만 끊고 보유는 유지하므로 폐기는 교체로 한다.
        thumbnails.update(document: .empty)
        isLoading = true
        #if !os(macOS)
            // 시트는 사용자가 열 때만 뜬다 — 새 문서를 열면 닫힌 상태로 돌아간다.
            sidebarVisible = false
        #endif
        loadProgress = nil
        loadGeneration += 1
        // 어느 경로로 열든 대기 중인 드롭 완료를 무효화한다 — fileImporter·최근
        // 문서로 새 문서를 연 뒤 느린 드롭이 도착해 그것을 덮지 않게 (#126).
        openGeneration += 1
        // 무효화한 완료를 기다릴 이유도 없다 — 전송 자체를 끊는다 (방금 성공을
        // 전달한 드롭 요청이면 이미 끝난 Progress라 무해).
        dropRequest?.cancel()
        dropRequest = nil
        let generation = loadGeneration
        let didStart = url.startAccessingSecurityScopedResource()
        loadTask = Task {
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            var didRecordRecent = false
            var loadFailed = false
            do {
                // 프로그레시브 로딩: 첫 페이지 확정 즉시 표시, 잔여 페이지는
                // 배치 스냅샷으로 이어 붙는다 (뷰가 loadToken으로 증분 적용).
                let loader = HwpDocumentLoader()
                for try await snapshot in await loader.loadUpdates(from: url) {
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard generation == loadGeneration else { return }
                        if document == nil {
                            currentPage = 1
                            zoomScale = 1.0
                            // 옛 문서를 향한 맞춤 요청이 새 문서에 적용되지 않게
                            // 함께 비운다 (뷰는 문서 세대로 한 번 더 거른다).
                            fitZoom = nil
                        }
                        document = snapshot.document
                        // 스냅샷마다 넘겨도 프로그레시브 증분이면 라이브러리가
                        // 알아보고 이미 그린 축소판을 유지한다 (같은 loadToken +
                        // 쪽 수 비감소). 사이드바가 닫혀 있어도 갱신해 둬야
                        // 나중에 여는 순간 최신 쪽 수로 열린다.
                        thumbnails.update(document: snapshot.document)
                        loadProgress = snapshot.isComplete ? nil : snapshot.progress
                        isLoading = false
                    }
                    // 추월 검사가 기록보다 **먼저**다 — 위 MainActor.run의 가드는
                    // UI 적용만 건너뛰고 실행은 여기로 흘러오므로, 검사를 기록
                    // 뒤에 두면 화면에 뜬 적 없는 문서가 목록에 오르고, 나중에
                    // 기록되는 만큼 표시 중인 새 문서보다 위로 올라간다.
                    if generation != loadGeneration {
                        break
                    }
                    // 첫 스냅샷이 나온 **뒤** 한 번만 기록한다 (#126) — 파싱에
                    // 실패하는 파일은 목록에 들어가지 않고, 보안 범위 접근이
                    // 살아 있는 이 task가 북마크를 만들 수 있는 유일한 시점이다.
                    if !didRecordRecent {
                        didRecordRecent = true
                        if let updated = RecentDocumentsStore.record(url: url) {
                            await MainActor.run { recents = updated }
                        }
                    }
                }
            } catch is CancellationError {
                // 취소된 로드는 조용히 종료 (새 로드가 UI를 갱신한다)
            } catch {
                loadFailed = true
                await MainActor.run {
                    guard generation == loadGeneration else { return }
                    errorMessage = "\(error)"
                    isLoading = false
                    loadProgress = nil
                }
            }
            // 버려진 로드의 드롭 사본은 여기서 지운다 — 실패했거나(오류 화면)
            // 추월당한(취소·세대 전진 — 취소는 언제나 새 로드가 하므로 세대
            // 검사가 포섭한다) 사본은 아무것도 뒷받침하지 않는다. 완주해 표시
            // 중인 문서의 사본만 기존 정책대로 다음 실행의 잔해 청소에 남는다.
            if isOwnedDropCopy, loadFailed || generation != loadGeneration {
                DropOpenSupport.discardCopy(at: url)
            }
        }
    }
}
