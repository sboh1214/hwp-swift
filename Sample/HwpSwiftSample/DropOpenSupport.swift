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

    /// `.fileURL`을 함께 받는 이유: Finder 드래그는 파일 URL 타입으로 오고
    /// 콘텐츠 타입 적합성은 보장되지 않는다. 대신 아무 파일이나 드롭이
    /// 활성화되므로, 확장자 검증은 `open(providers:)`가 맡는다.
    static var acceptedTypes: [UTType] {
        [hwpType, .fileURL]
    }

    /// providers에서 열 수 있는 첫 항목의 URL을 만들어 main으로 돌려준다.
    /// 반환 false는 처리할 provider가 없다는 뜻이다 (드롭 거절).
    static func open(
        providers: [NSItemProvider],
        completion: @escaping @MainActor (Result<URL, DropOpenFailure>) -> Void
    ) -> Bool {
        // 파일 URL 경로를 먼저 본다 — 원본 위치를 알아야 최근 문서에 남는다.
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                let result: Result<URL, DropOpenFailure> =
                    if let url, url.pathExtension.lowercased() == "hwp" {
                        .success(url)
                    } else if url != nil {
                        .failure(.notHwp)
                    } else {
                        .failure(.unreadable)
                    }
                Task { @MainActor in completion(result) }
            }
            return true
        }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(hwpType.identifier)
        }) {
            provider.loadFileRepresentation(forTypeIdentifier: hwpType.identifier) { url, _ in
                // 이 URL의 파일은 핸들러가 반환되면 사라진다 — 복사는 여기서
                // **동기로** 끝내야 한다.
                let result: Result<URL, DropOpenFailure> =
                    if let url, let copy = try? copyToTemporary(url) {
                        .success(copy)
                    } else {
                        .failure(.unreadable)
                    }
                Task { @MainActor in completion(result) }
            }
            return true
        }
        return false
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
    /// 서로 덮어쓰지 않고, 원본 파일명이 보존돼 창 제목·내보내기 이름에 쓰인다.
    private static func copyToTemporary(_ url: URL) throws -> URL {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("\(dropCopyPrefix)\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try manager.copyItem(at: url, to: destination)
        return destination
    }
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
