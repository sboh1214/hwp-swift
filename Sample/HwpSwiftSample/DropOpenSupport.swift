import Foundation
import UniformTypeIdentifiers

/// 드래그앤드롭으로 받은 provider에서 열 `.hwp` 파일 URL을 뽑는다 (#126).
///
/// 경로가 플랫폼마다 다르다:
/// - macOS(Finder)는 드래그 페이스트보드가 **파일 URL**을 싣고 샌드박스 접근
///   확장이 함께 오므로, 그 URL을 원본 그대로 연다 (최근 문서 기록도 된다).
/// - iOS(Files 등)는 URL 대신 **파일 표현**을 준다. 그 파일은 완료 핸들러가
///   반환되면 시스템이 지우므로, 핸들러 안에서 앱 임시 디렉터리로 복사한 뒤
///   그 사본을 연다 (임시 경로라 최근 문서에는 기록되지 않는다 —
///   `RecentDocumentsStore.record`의 임시 디렉터리 제외 규칙).
enum DropOpenSupport {
    /// `.hwp` 콘텐츠 타입 — `Info.plist`의 imported 선언과 같은 식별자다.
    static let hwpType = UTType(importedAs: "dev.sboh.hwp")

    /// 드롭 사본 디렉터리 접두사. 사본은 문서가 열려 있는 동안 살아야 하므로
    /// 세션 중에는 지우지 않고, 다음 실행의 시작 시 잔해 청소가 이 접두사로
    /// 찾아 거둔다 (내보내기 임시 PDF와 같은 정책).
    static let dropCopyPrefix = "hwp-sample-drop-"

    /// `.fileURL`·`.data`를 함께 받는 이유: Finder 드래그는 파일 URL 타입으로
    /// 오고 콘텐츠 타입 적합성은 보장되지 않으며, iOS에서는 `.hwp` 확장자에
    /// 자체 UTI를 export하는 앱이 설치된 기기에서 Files 드래그 항목의 타입이
    /// 그쪽 식별자가 되어 `hwpType`에 적합하지 않다. 대신 아무 파일이나 드롭이
    /// 활성화되므로, 확장자 검증은 `open(providers:)`가 맡는다.
    static var acceptedTypes: [UTType] {
        [hwpType, .fileURL, .data]
    }

    /// providers에서 열 수 있는 항목의 URL을 만들어 main으로 돌려준다.
    /// 반환 nil은 처리할 provider가 없다는 뜻이고(드롭 거절), 값은 진행 중
    /// 적재의 취소 손잡이다 — 추월·뷰 해체 시 호출자가 취소한다.
    static func open(
        providers: [NSItemProvider],
        completion: @escaping @MainActor (Result<DropOpenedFile, DropOpenFailure>) -> Void
    ) -> DropOpenRequest? {
        let ordered = candidates(in: providers)
        guard !ordered.isEmpty else { return nil }
        let request = DropOpenRequest()
        openNext(ordered, at: 0, request: request, lastFailure: .unreadable, completion: completion)
        return request
    }

    /// 드롭 후보 한 건 — provider와 그것을 여는 방법.
    private struct Candidate {
        let provider: NSItemProvider
        /// nil이면 파일 URL 경로, 값이 있으면 그 식별자로 파일 표현을 요청한다.
        let fileRepresentationType: String?
    }

    /// 후보를 **하나의 순서열**로 만든다 — 적합성 버킷마다 따로 `first(where:)`로
    /// 뽑으면 앞선 비-hwp 하나가 뒤의 유효한 문서를 가린다 (외래 UTI로 오는
    /// `.hwp`와 아무 파일은 둘 다 `public.data`에만 적합해 같은 버킷에 들어간다).
    ///
    /// 파일 URL이 앞인 것은 원본 위치를 알아야 최근 문서에 남기 때문이다. 같은
    /// provider가 URL·표현 양쪽에 오를 수 있는데, 앞 경로가 URL을 못 내줘도 뒤
    /// 경로가 성공할 수 있으므로 의도된 중복이다.
    private static func candidates(in providers: [NSItemProvider]) -> [Candidate] {
        let urlCandidates = providers
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            .map { Candidate(provider: $0, fileRepresentationType: nil) }
        let representationCandidates = providers.compactMap { provider -> Candidate? in
            if provider.hasItemConformingToTypeIdentifier(hwpType.identifier) {
                return Candidate(provider: provider, fileRepresentationType: hwpType.identifier)
            }
            // 외래 UTI 폴백 — 파일 표현이 원본 파일명을 보존하므로 확장자 검증이
            // 그대로 성립한다 (`.fileURL` 경로와 같은 "넓게 받고 검증" 정책).
            if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                return Candidate(
                    provider: provider, fileRepresentationType: UTType.data.identifier
                )
            }
            return nil
        }
        return urlCandidates + representationCandidates
    }

    /// 후보를 앞에서부터 소진하며 첫 `.hwp`를 연다. 실패 사유는 마지막까지
    /// 하나도 못 열었을 때만 전달한다 — 읽긴 했는데 확장자가 아니었으면
    /// `.notHwp`가 `.unreadable`보다 정확한 사유라, 한 번 잡히면 유지된다.
    private static func openNext(
        _ candidates: [Candidate],
        at index: Int,
        request: DropOpenRequest,
        lastFailure: DropOpenFailure,
        completion: @escaping @MainActor (Result<DropOpenedFile, DropOpenFailure>) -> Void
    ) {
        // 취소가 부른 적재 실패 콜백이 다음 후보의 전송을 새로 시작하지 않게
        // 여기서 끊는다. 완료는 부르지 않는다 — 취소자는 결과를 받지 않기로
        // 한 쪽이다.
        guard !request.isCancelled else { return }
        guard index < candidates.count else {
            Task { @MainActor in completion(.failure(lastFailure)) }
            return
        }
        let candidate = candidates[index]
        guard let typeIdentifier = candidate.fileRepresentationType else {
            let progress = candidate.provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.pathExtension.lowercased() == "hwp" {
                    Task { @MainActor in
                        completion(.success(DropOpenedFile(url: url, isOwnedCopy: false)))
                    }
                    return
                }
                openNext(
                    candidates,
                    at: index + 1,
                    request: request,
                    lastFailure: url != nil ? .notHwp : lastFailure,
                    completion: completion
                )
            }
            request.advance(to: progress)
            return
        }
        let progress = candidate.provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            // 이 URL의 파일은 핸들러가 반환되면 사라진다 — 복사는 여기서
            // **동기로** 끝내야 한다.
            guard let url else {
                openNext(
                    candidates, at: index + 1, request: request,
                    lastFailure: lastFailure, completion: completion
                )
                return
            }
            // 이름의 권위는 임시 URL이 아니라 provider다 — `loadFileRepresentation`은
            // "임시 위치에 사본을 쓴다"만 약속하고 원본 파일명 보존은 약속하지 않는다.
            let name = suggestedFilename(of: candidate.provider, fallback: url)
            let nameIsHwp = (name as NSString).pathExtension.lowercased() == "hwp"
            // 앱 선언 타입으로 온 후보는 provider가 이미 HWP라고 **광고**한 것이라
            // 확장자를 다시 요구하지 않는다. 그러면 이름을 UUID로 바꿔 주는
            // provider의 유효한 문서를 거부하게 된다. `.data` 폴백의 확장자
            // 검증은 광고 이름과 표현 URL **어느 쪽이든** 통과면 받는다 —
            // 표시 이름 선호와 검증은 별개라, 광고 이름 하나에 걸면 확장자
            // 없는 제목형 suggestedName이 URL은 `document.hwp`인 유효 문서를
            // 거부한다.
            let urlIsHwp = url.pathExtension.lowercased() == "hwp"
            guard typeIdentifier == hwpType.identifier || nameIsHwp || urlIsHwp else {
                openNext(
                    candidates, at: index + 1, request: request,
                    lastFailure: .notHwp, completion: completion
                )
                return
            }
            guard let copy = try? copyToTemporary(
                url, as: nameIsHwp ? name : name + ".hwp"
            ) else {
                openNext(
                    candidates, at: index + 1, request: request,
                    lastFailure: lastFailure, completion: completion
                )
                return
            }
            Task { @MainActor in
                completion(.success(DropOpenedFile(url: copy, isOwnedCopy: true)))
            }
        }
        request.advance(to: progress)
    }

    /// 사본에 쓸 파일명 — provider가 광고한 이름을 먼저 보고, 없으면 임시 URL의
    /// 이름으로 물러선다. 창 제목·최근 문서·내보내기 기본 이름이 이 값을 그대로
    /// 물려받는다.
    private static func suggestedFilename(of provider: NSItemProvider, fallback url: URL) -> String {
        if let advertised = sanitizedComponent(provider.suggestedName) {
            return advertised
        }
        return sanitizedComponent(url.lastPathComponent) ?? "document"
    }

    /// 파일명으로 쓸 수 있는 단일 성분만 통과시킨다 — provider가 준 이름에 경로
    /// 구분자가 섞여 있으면 사본이 UUID 디렉터리 밖을 가리킬 수 있다.
    private static func sanitizedComponent(_ name: String?) -> String? {
        guard let name else { return nil }
        let component = (name as NSString).lastPathComponent
        guard !component.isEmpty, component != ".", component != ".." else { return nil }
        return component
    }

    /// 소유 사본을 디렉터리째 지운다 — 스테일 가드가 성공 값을 버리면 그
    /// 참조가 마지막인데, `removeStaleDropCopies`는 이전 실행 것만 거두므로
    /// 여기서 지우지 않으면 이번 세션 내내 쌓인다. 소유 판정은 호출자가
    /// `DropOpenedFile.isOwnedCopy`로 하고, 여기의 경로 형태 검사는 삭제
    /// 경로의 **이중 게이트**다 — 어느 한쪽이 잘못돼도 원본은 지워지지 않는다.
    static func discardCopy(at url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        guard directory.lastPathComponent.hasPrefix(dropCopyPrefix),
              directory.deletingLastPathComponent().standardizedFileURL.path
              == manager.temporaryDirectory.standardizedFileURL.path
        else { return }
        try? manager.removeItem(at: directory)
    }

    /// 이전 실행이 남긴 드롭 사본을 거둔다. 항목 판별이 접두사뿐인 것은
    /// `ContentView.removeStaleExports`의 임시 PDF와 같은 이유다 — 이번 실행
    /// 것은 열려 있는 문서가 읽고 있을 수 있어 건드리지 않는다.
    static func removeStaleDropCopies(olderThan processStart: Date) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(dropCopyPrefix) {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let modified, modified < processStart else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    /// 드롭 파일을 UUID 하위 디렉터리로 복사한다 — 같은 이름을 연달아 드롭해도
    /// 서로 덮어쓰지 않는다. 이름은 호출자가 정한다 (`suggestedFilename`).
    private static func copyToTemporary(_ url: URL, as filename: String) throws -> URL {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("\(dropCopyPrefix)\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        do {
            try manager.copyItem(at: url, to: destination)
        } catch {
            // 디스크 고갈 등으로 부분 파일이 남을 수 있다 — 호출자는 URL을 못
            // 받아 어떤 청소도 닿지 않으므로 여기서 디렉터리째 되감는다
            // (`removeStaleDropCopies`는 이번 실행 것을 건너뛴다).
            try? manager.removeItem(at: directory)
            throw error
        }
        return destination
    }
}

/// 진행 중 드롭 적재의 취소 손잡이. 완료 무효화(세대 검사)는 결과만 버리고
/// 전송은 계속 돌므로 — iCloud 대형 파일이면 전량 내려받는다 — 추월·뷰 해체
/// 시 호출자가 이것으로 전송 자체를 끊는다.
///
/// provider 적재는 후보마다 새 `Progress`를 내므로 `advance`가 현재 것을
/// 갈아 끼우고, `cancel()`과의 경주는 "취소 뒤 도착한 Progress도 즉시 취소"로
/// 닫는다 — cancel(main)과 advance(적재 콜백 큐)가 다른 큐에서 와 락이 필요하다.
final class DropOpenRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var current: Progress?

    func cancel() {
        lock.lock()
        cancelled = true
        let progress = current
        lock.unlock()
        progress?.cancel()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func advance(to progress: Progress) {
        lock.lock()
        current = progress
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            progress.cancel()
        }
    }
}

/// 드롭 열기 성공 값 — URL과 그 **출처**. 스테일 폐기가 소유 사본만 지우도록
/// 출처를 함께 나른다: 경로 형태는 소유의 증명이 아니다 (파일 URL 경로가
/// 사본 형태의 경로를 내줄 수도 있다).
struct DropOpenedFile {
    let url: URL
    /// 이 앱이 만든 임시 사본(파일 표현 경로)이면 true. 원본(파일 URL 경로)은
    /// false — 스테일 폐기가 절대 지우면 안 된다.
    let isOwnedCopy: Bool
}

enum DropOpenFailure: Error {
    /// 드롭된 파일이 `.hwp`가 아니다.
    case notHwp
    /// provider가 URL도 파일 표현도 내주지 못했다 (또는 사본 생성 실패).
    case unreadable

    var message: String {
        switch self {
        case .notHwp: ".hwp 파일만 열 수 있습니다."
        case .unreadable: "드롭한 파일을 읽지 못했습니다."
        }
    }
}
