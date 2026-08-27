import Foundation

/// 최근 문서 한 항목 (#126). 이름·경로는 표시·중복 판정용이고 **북마크가 실제
/// 참조**다 — `fileImporter`가 준 샌드박스 접근 권한은 프로세스가 끝나면
/// 사라지므로, 경로 문자열만 저장하면 다음 실행에서 같은 파일을 열 수 없다.
/// 보안 범위 북마크가 권한까지 함께 저장하는 유일한 통로다.
struct RecentDocument: Codable, Hashable, Identifiable {
    /// 같은 파일을 다시 열어 북마크가 갱신돼도 항목이 유지되도록 id는 경로다.
    var id: String {
        path
    }

    /// 파일 이름 (`lastPathComponent`).
    let name: String
    /// 표준화된 파일 경로. 픽스처가 전부 `document.hwp`라 이름만으로는 항목이
    /// 구별되지 않는다 — 폴더 표시(`folderDisplayName`)가 그 구별을 맡는다.
    let path: String
    let bookmark: Data

    /// 목록 보조 행에 보일 폴더 이름. macOS는 홈을 `~`로 줄인 전체 경로가
    /// 유용하지만, iOS 컨테이너 경로는 길고 무의미해 마지막 폴더명만 보인다.
    var folderDisplayName: String {
        let folder = (path as NSString).deletingLastPathComponent
        #if os(macOS)
            // `abbreviatingWithTildeInPath`를 쓰지 않는 이유: 샌드박스에서
            // `NSHomeDirectory()`는 컨테이너 경로라 실사용자 경로는 줄지 않고,
            // 반대로 컨테이너 안 경로가 실제 홈처럼 `~`로 위장된다. 실제
            // 홈(getpwuid)으로 직접 줄인다.
            if let home = Self.realHomeDirectory,
               folder == home || folder.hasPrefix(home + "/")
            {
                return "~\(folder.dropFirst(home.count))"
            }
            return folder
        #else
            return (folder as NSString).lastPathComponent
        #endif
    }

    #if os(macOS)
        private static let realHomeDirectory: String? = {
            guard let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir else {
                return nil
            }
            return String(cString: home)
        }()
    #endif
}

/// `UserDefaults` 기반 최근 문서 저장소. 진실 원본은 defaults이고 각 창의
/// `@State`는 거울이다 — 기록·제거가 갱신된 목록을 돌려주므로 호출한 창이
/// 그 값으로 거울을 맞추고, `WindowGroup`의 다른 창은 defaults 변경 알림으로
/// 따라온다 (`ContentView`의 `onReceive`).
enum RecentDocumentsStore {
    static let maxCount = 10
    private static let defaultsKey = "recentDocuments"

    static func load() -> [RecentDocument] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let documents = try? JSONDecoder().decode([RecentDocument].self, from: data)
        else { return [] }
        return documents
    }

    /// 성공적으로 연 문서를 목록 맨 앞에 기록하고 갱신된 목록을 돌려준다.
    /// 기록하지 않았으면 nil이다 (임시 파일이거나 북마크 생성 실패).
    ///
    /// - 보안 범위 접근이 **살아 있는 동안** 불러야 한다 — 북마크 생성이 그
    ///   권한을 캡슐에 담는 시점이기 때문이다 (`loadDocument`의 로드 task 안).
    /// - 임시 디렉터리의 파일(드롭 복사본 등)은 기록하지 않는다 — 프로세스가
    ///   끝나면 죽는 경로라 목록을 열리지 않는 항목으로 채운다.
    /// - 중복 판정은 경로다. 파일이 이동하면 옛 경로 항목이 남을 수 있지만,
    ///   그 항목은 다시 눌러도 북마크가 새 위치를 찾아 열리고 상한(10개)이
    ///   밀어내며 자연히 거둔다.
    static func record(url: URL) -> [RecentDocument]? {
        let standardized = url.standardizedFileURL
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        guard !standardized.path.hasPrefix(temporary) else { return nil }
        guard let bookmark = try? standardized.bookmarkData(options: creationOptions) else {
            return nil
        }
        let entry = RecentDocument(
            name: standardized.lastPathComponent,
            path: standardized.path,
            bookmark: bookmark
        )
        var documents = load().filter { $0.path != entry.path }
        documents.insert(entry, at: 0)
        documents = Array(documents.prefix(maxCount))
        save(documents)
        return documents
    }

    /// 항목을 제거하고 갱신된 목록을 돌려준다 (죽은 북마크 정리·사용자 요청).
    static func remove(_ document: RecentDocument) -> [RecentDocument] {
        let documents = load().filter { $0.id != document.id }
        save(documents)
        return documents
    }

    /// `resolve`의 결과. **URL로 풀리는 것과 읽을 수 있는 것이 다르다** — 재부팅
    /// 뒤 iOS 북마크는 URL은 내주면서 접근 권한은 잃는다 (`creationOptions` 참조).
    /// 둘을 합쳐 옵셔널로 두면 그 차이가 사라져, 눌러도 매번 실패하는 행이
    /// 목록에 남는다.
    enum Resolution {
        case resolved(URL)
        /// URL은 풀렸지만 읽을 수 없다 — 권한 만료(재부팅)나 미다운로드.
        case inaccessible
        /// 북마크가 URL로 풀리지 않는다 — 파일 삭제 등.
        case unavailable
    }

    /// 북마크를 URL로 되살리고 **실제로 읽을 수 있는지까지** 확인한다.
    ///
    /// 낡은(stale) 북마크는 여기서 재발급하지 않는다: 되살린 URL로 문서가
    /// 열리면 `record`가 어차피 새 북마크로 재기록한다.
    static func resolve(_ document: RecentDocument) -> Resolution {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: document.bookmark,
            options: resolutionOptions,
            bookmarkDataIsStale: &isStale
        ) else { return .unavailable }
        // 읽기 확인은 범위를 쥔 채로 해야 한다 — macOS의 보안 범위 URL은
        // `startAccessing` 없이 읽히지 않는다.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .inaccessible
        }
        return .resolved(url)
    }

    /// 보안 범위 북마크 옵션은 macOS 전용이다 —
    /// `NSURLBookmarkCreationWithSecurityScope`가 iOS에서 `API_UNAVAILABLE`이라
    /// 옵션 없이 만드는 것 말고는 선택지가 없다.
    ///
    /// **그 대가가 수명이다.** 보안 범위 없이 만든 북마크는 implicit ephemeral
    /// security scope를 자동으로 다는데, SDK 문서(`NSURL.h`의
    /// `WithoutImplicitSecurityScope` 항목)가 그 범위를 "valid until reboot at
    /// the latest"라고 못박는다. 즉 iOS에서 이 목록의 접근 권한은 재부팅을 넘기지
    /// 못하고, 그때 북마크는 URL로는 여전히 풀린다 — `resolve`가 읽기 가능
    /// 여부까지 보는 이유다.
    private static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
            [.withSecurityScope]
        #else
            []
        #endif
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
            [.withSecurityScope]
        #else
            []
        #endif
    }

    private static func save(_ documents: [RecentDocument]) {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
