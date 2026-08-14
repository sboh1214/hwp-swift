import Foundation

/// 문서 탐색 항목 하나 — 개요(제목) 문단이거나 책갈피다 (#77).
///
/// 사이드바·목차·VoiceOver 로터처럼 "그 자리로 간다"가 목적인 UI의 재료다.
/// 조판이 확정한 쪽을 들고 있으므로 호스트는 `pageNumber`를
/// `HwpPageNavigator.currentPage`(1-기반)에 그대로 쓰거나 `pageIndex`를 네이티브
/// 뷰(0-기반)에 넘기면 된다.
///
/// 목록은 `HwpDocumentMetadata.outline`에 **문서 순서**로 담긴다. 라이브러리는
/// 목록 UI를 제공하지 않는다 (`Sources/HwpKit/AGENTS.md`의 "v1 스코프 밖" —
/// 검색 결과 목록과 같은 기준). 대신 `Identifiable` + 1-기반 쪽 번호 +
/// 수준까지 채워 두므로 호스트가 `List`로 열 줄 안에 만든다:
///
/// ```swift
/// List(document.metadata.outline) { item in
///     Button(item.title) { currentPage = item.pageNumber }
///         .padding(.leading, CGFloat((item.level ?? 1) - 1) * 12)
/// }
/// ```
public struct HwpOutlineItem: Sendable, Hashable, Identifiable {
    /// 항목의 출처.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// 개요 문단 (문단 머리 모양 종류 1) 또는 `개요 N` 스타일 문단.
        /// **최상위 본문 문단만** 대상이다 — 표 셀·글상자·각주 안의 개요 문단은
        /// 목차 항목이 아니다 (문서의 목차는 본문 흐름의 제목 계층이다).
        case heading
        /// 책갈피 컨트롤 (`bokm`). 앵커라 어디에 놓이든 목적지이므로 본문
        /// 컨테이너(각주·표 셀·글상자·중첩 표) 안까지 모은다 — 머리말/꼬리말만
        /// 뺀다 (검색과 같은 스코프 규약).
        case bookmark
    }

    /// 제목 문자열의 상한 (Character 기준). 목록은 탐색용이라 긴 문단이
    /// 통째로 metadata에 상주하면 안 된다 — 병적 입력에서 항목 하나가
    /// 수 MB가 되는 것을 막는다. 자를 때 말줄임표를 붙이지 않으므로
    /// `title`은 언제나 문단 평문의 **접두**다 (표시용 말줄임은 호스트 몫).
    public static let titleCharacterLimit = 200

    /// 개요 수준의 상한 (1-기반). 비트 경로(표 44 bit 25-27)는 3비트라 1...8이고
    /// 한글 기본 스타일이 `개요 1`~`개요 10`이므로 이 값이 두 경로를 모두 덮는다.
    ///
    /// 상한을 넘는 이름의 사용자 스타일(`개요 12`)은 **거부가 아니라 클램프**다 —
    /// 거부하면 그 제목이 목록에서 조용히 사라지는데, 수준은 들여쓰기 힌트일 뿐이고
    /// 쪽 번호는 그대로라 탐색은 성립한다. 호스트가 수준을 들여쓰기 배수로 쓸 때의
    /// 상한이기도 하다.
    public static let maximumLevel = 10

    public let kind: Kind
    /// 화면에 보일 이름 — 개요는 문단 평문(컨트롤 문자 제거·공백 정규화),
    /// 책갈피는 `HwpOtherControlBookmarkInfo.name`. 언제나 비어 있지 않다
    /// (빈 제목 항목은 누를 곳만 있고 읽을 것이 없어 수집 단계에서 버린다).
    public let title: String
    /// 개요 수준 — **1-기반**(`개요 N`의 N). 책갈피는 nil.
    ///
    /// CoreHwp의 `HwpParaShapeProperty1.headingLevelRawValue`는 저장값 그대로
    /// **0-기반**이다. 두 기점을 한 필드에 섞지 않으려고 여기서 `+ 1` 해 둔다 —
    /// 스타일 이름 폴백(`개요 3` → 3)이 자연히 1-기반이라 그쪽에 맞췄다.
    /// 값은 언제나 `1...maximumLevel` 안이다 — 비트 경로가 1...8이고 스타일 이름
    /// 폴백은 그 상한으로 클램프된다. 호스트가 들여쓰기 배수로 써도 안전하다.
    public let level: Int?
    /// **1-기반** 쪽 번호 — `HwpPageNavigator.currentPage`·
    /// `HwpUnsupportedElement.page`와 같은 규약.
    ///
    /// **개요와 책갈피는 서로 다른 시점을 잡는다.** 개요는 그 문단이 **시작한**
    /// 쪽이고(쪽 경계를 걸친 제목이 뒷쪽으로 밀리지 않게 배치 **전** 값을 쓴다),
    /// 책갈피는 앵커가 **놓인** 쪽이다(배치 **후** 값 — 진단
    /// `walkUnsupported`와 같은 기준). 표·글상자·각주 **안**의 책갈피는 그
    /// 컨테이너를 품은 본문 문단이 놓인 쪽으로 보고되므로, 여러 쪽에 걸친 표
    /// 안에서는 실제 셀이 그려진 쪽과 다를 수 있다.
    ///
    /// **미주 안의 책갈피는 그 오차가 무한정이다** — 미주는 구역·문서 끝에
    /// 배치되는데 이 값은 참조 문단의 쪽이라 수백 쪽 앞을 가리킬 수 있다.
    /// 정확히 귀속하려면 이미 발행된 항목을 사후 갱신해야 하는데, 그것은
    /// `ordinal` 접두 안정성과 충돌한다 (루트 `AGENTS.md`의 "개요·책갈피 탐색").
    public let pageNumber: Int
    /// 문서 순서 서수 (0부터). 같은 제목이 여러 번 나와도 항목을 가른다.
    ///
    /// 프로그레시브 로딩의 중간 스냅샷은 확정된 접두만 담고 수집은 append-only라
    /// 서수가 스냅샷 사이에서 움직이지 않는다 — SwiftUI `List` 신원이 로딩 중에
    /// 흔들리지 않는 근거다.
    public let ordinal: Int

    public init(
        kind: Kind,
        title: String,
        level: Int?,
        pageNumber: Int,
        ordinal: Int
    ) {
        self.kind = kind
        self.title = title
        self.level = level
        self.pageNumber = pageNumber
        self.ordinal = ordinal
    }

    /// `Identifiable` 신원 — 문서 순서 서수. 한 문서의 `outline` 안에서 유일하다.
    public var id: Int {
        ordinal
    }

    /// **0-기반** 쪽 인덱스 — `HwpTextPosition.pageIndex`·네이티브 뷰와 같은
    /// 좌표계. (`HwpSearchMatch`의 `pageIndex`/`pageNumber` 쌍과 같은 규약.)
    public var pageIndex: Int {
        pageNumber - 1
    }
}

/// 목록 UI가 흔히 하는 갈래 나누기 — `Element == HwpOutlineItem`으로 좁힌
/// 확장이라 다른 컬렉션에는 보이지 않는다.
public extension Collection<HwpOutlineItem> {
    /// 개요 문단 항목만 (문서 순서 유지).
    var headings: [HwpOutlineItem] {
        filter { $0.kind == .heading }
    }

    /// 책갈피 항목만 (문서 순서 유지).
    var bookmarks: [HwpOutlineItem] {
        filter { $0.kind == .bookmark }
    }

    /// 그 쪽(**1-기반** — `pageNumber`와 같은 규약)의 항목만 (문서 순서 유지).
    func items(onPage pageNumber: Int) -> [HwpOutlineItem] {
        filter { $0.pageNumber == pageNumber }
    }
}
