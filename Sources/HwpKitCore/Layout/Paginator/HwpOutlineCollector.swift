import CoreHwp
import Foundation

/// 조판 중에 개요(제목) 문단과 책갈피를 모아 `HwpDocumentMetadata.outline`을
/// 만드는 수집기 (#77).
///
/// `HwpPaginator`가 문단 배치를 확정할 때마다 불린다 — 쪽 귀속이 조판의
/// 함수이므로 파서 단독으로는 만들 수 없고, 렌더 결과에서 사후 복원할 수도
/// 없다 (`HwpParaHeader.paraId`는 "unique ID"라는 doc-comment와 달리 실측이
/// 정반대다: 헌법주석 문단 14,660개의 distinct `paraId`가 2,020개뿐이고
/// `0x80000000` 한 값이 12,580회 나온다. `noori`는 문단 65개에 distinct
/// `paraId`가 2개다).
///
/// 본체(2,800줄)가 아니라 별도 파일에 두는 것은 관례이자 필수다 — swiftlint
/// `file_length` error가 700이라 기존 `Paginator/` 파일에 얹으면 Lint가
/// 떨어진다.
///
/// **중복 수집을 막는 것은 페이지네이션이 일회성이라는 기존 불변식이다** —
/// `HwpPaginator`는 `didFinishPagination`을 되돌리지 않고 재조판(줌·리사이즈·
/// 문서 교체)은 새 paginator를 만든다 (`HwpDocumentActor.buildDocument`가
/// 유일한 생성 지점). `collectedUnsupported`가 리셋 없이 성립하는 것과 같은
/// 근거이므로, 나중에 같은 인스턴스를 다시 조판하게 만든다면 그 둘을 **함께**
/// 비워야 한다 (가드: `HwpOutlineCollectorTests`의 반복 조판 테스트).
struct HwpOutlineCollector {
    /// paragraph-bearing 컨테이너의 단일 traversal 지점 주입
    /// (`HwpPaginator.childParagraphs(of:)` — unsupported walk/렌더 경로와 공유).
    typealias ChildParagraphs = (CoreHwp.HwpCtrlId) -> [(CoreHwp.HwpParagraph, HwpBlockKind)]

    /// 컨테이너 안 컨테이너 재귀 상한 — 렌더·진단 walk와 같은 값을 쓴다.
    /// **표는 이 한도를 타지 않는다** — `HwpTableLayout.maximumNestingDepth`가
    /// 따로 있고 렌더·진단이 그것을 쓰므로 수집기도 같이 가른다
    /// (`collectBookmarks`).
    static let maximumContainerDepth = HwpPaginator.maximumContainerDepth

    /// 목록 항목 수 상한. 페이지 상한(`HwpPaginator.maximumDocumentPages`)과 같은
    /// 성격의 방어다 — 항목마다 최대 `titleCharacterLimit`짜리 문자열이 metadata에
    /// 상주하므로, 병적 입력이 목록만으로 메모리를 고갈시키지 못하게 자른다.
    /// **페이지 상한이 이것을 대신하지 못한다**: 0-높이 문단은 쪽을 늘리지 않고도
    /// 무한히 이어질 수 있다. 실측 최대는 헌법주석의 1,944개이므로 10배 여유를
    /// 두고 자른다. 항목 하나의 상한은 `titleCharacterLimit`(200자)이 아니라
    /// `titleUnitCeiling`이다 — grapheme 하나가 임의로 길 수 있어 200자가
    /// byte 상한이 되지 못한다 (최악 20,000 × 6,400 단위).
    static let maximumItems = 20000

    /// 제목·책갈피 이름 수집의 **안전판** (UTF-16 단위). 상한
    /// (`titleCharacterLimit`)은 Character(grapheme) 단위라 UTF-16 배수로
    /// **근사할 수 없다** — ZWJ 시퀀스는 grapheme당 4단위를 훌쩍 넘어서
    /// (가족 이모지 11단위) 종전의 4배 컷은 상한에 한참 못 미치는 자리에서
    /// 끊었다 (이모지 100자 제목이 72자로). 그래서 이 값은 상한이 아니라
    /// **병적으로 긴 입력에서 O(입력 길이) 문자열을 만들지 않기 위한 것**이고,
    /// 표시 상한은 `collapsedWhitespace`의 Character prefix가 건다.
    ///
    /// **두 경로가 모두 이 천장을 지나야 한다.** 책갈피 이름은 Character 상한이
    /// 못 묶는다 — 기반 문자 하나에 결합 문자를 붙이면 128KB가 1자로 세어진다.
    ///
    /// 어떤 값을 골라도 grapheme 하나가 이보다 길면 (결합 문자를 무한히 붙일 수
    /// 있다) 결과가 상한보다 짧아진다 — O(1) 경계와 양립 불가한 한계이고, 그때도
    /// 결과는 원문의 접두다.
    static let titleUnitCeiling = HwpOutlineItem.titleCharacterLimit * 32

    private let index: HwpIndex

    /// 수집 결과 (문서 순서). `ordinal`은 이 배열의 인덱스와 같다.
    private(set) var items: [HwpOutlineItem] = []

    /// 스타일 이름 → 수준 메모 (`paraStyleId` 키, **nil도 캐시**). 스타일 이름은
    /// 최대 65,535 UTF-16 단위(STYLE 레코드의 길이 필드가 WORD)라 문단마다
    /// trim + 소문자 사본을 뜨면 이름 길이 × 문단 수로 증폭한다 — 개요가 아닌
    /// 문단은 두 이름을 **모두** 훑으므로 (`??`가 왼쪽 nil에서 오른쪽을 평가한다)
    /// 문단당 4벌이고, 그 nil이 가장 흔한 경로라 nil을 캐시하지 않으면 방어가
    /// 성립하지 않는다. 키가 `UInt8`이라 항목은 최대 256개다.
    private var styleLevelCache: [UInt8: Int?] = [:]
    /// 캐시 미스로 실제 이름을 훑은 횟수 — 테스트 전용 관측점.
    private(set) var styleParseCount = 0

    init(index: HwpIndex) {
        self.index = index
    }

    /// 문단 하나를 수집한다.
    ///
    /// - Parameters:
    ///   - paragraph: 방금 배치를 마친 본문 문단.
    ///   - headingPage: 개요 항목에 쓸 **1-기반** 쪽 — 문단이 **시작한** 쪽이다.
    ///     배치 후 값을 쓰면 쪽 경계를 걸친 제목이 뒷쪽으로 밀린다.
    ///   - bookmarkPage: 책갈피 항목에 쓸 **1-기반** 쪽 — 앵커가 **놓인** 쪽이다
    ///     (진단 `walkUnsupported`와 같은 기준).
    ///   - maximumPage: 문서에 남을 수 있는 마지막 쪽 (`HwpPaginator.maximumPages`).
    ///     **두 쪽 값을 각자 검사한다** — 하나로 묶으면 상한 쪽에서 시작해 다음
    ///     쪽으로 걸치는 제목이 버려진다: 배치 도중 `cacheCurrentPage`가 이미
    ///     상한을 채워 `bookmarkPage`는 밀려나지만 `headingPage`는 그대로
    ///     유효하다 (그 쪽은 캐시됐다).
    ///   - childParagraphs: 컨테이너 순회 주입.
    mutating func collect(
        from paragraph: CoreHwp.HwpParagraph,
        headingPage: Int,
        bookmarkPage: Int,
        maximumPage: Int,
        childParagraphs: ChildParagraphs
    ) {
        if headingPage <= maximumPage {
            collectHeading(from: paragraph, page: headingPage)
        }
        guard bookmarkPage <= maximumPage, let ctrls = paragraph.ctrlHeaderArray else { return }
        collectBookmarks(
            ctrls: ctrls,
            page: bookmarkPage,
            depth: 0,
            tableDepth: 0,
            childParagraphs: childParagraphs
        )
    }
}

// MARK: - 개요 문단

private extension HwpOutlineCollector {
    /// 개요 문단을 수집한다. 수준을 얻는 경로는 **둘이고 상시 병행**이다.
    ///
    /// ① 문단 머리 모양 종류가 개요(1)면 문단 수준 비트(표 44 bit 25-27).
    /// ② 아니면 스타일 이름 `개요 N` / `Outline N`.
    ///
    /// ②가 대안이 아니라 병행 경로인 이유는 비트 폭이 아니다 — `개요 8` 이상
    /// 스타일은 문단 머리 모양이 개요로 설정돼 있지 않아 (`headingType == 0`)
    /// **①로는 원리적으로 잡히지 않는다** (헌법주석 실측: 스타일 `개요 8`·
    /// `개요 9`가 둘 다 paraShape #24를 가리키고 그 raw는 `0x180`이다).
    ///
    /// 여기서 수집하는 문단이 `collectUnsupportedNumberingHeading`의 미지원
    /// 신고와 **동시에** 잡히는 것은 의도다. 그쪽은 "개요 번호 라벨을 렌더러가
    /// 만들지 않는다"를 알리는 진단이고, 탐색 대상으로 승격시켜도 라벨을
    /// 렌더하게 되는 것은 아니므로 그 신고는 유지되어야 한다.
    ///
    /// **옆에 있는 그 진단의 가드를 복사하면 안 된다** — 거기는
    /// `paraShape.numberingOrBulletId > 0`을 요구하는데 실문서 개요 paraShape의
    /// 그 값은 전 픽스처에서 0이다 (헌법주석의 개요 문단 1,944개가 쓰는 shape
    /// 전부 0). 그대로 베끼면 1,944개 중 0개가 수집되고 사이드바가 조용히 빈다.
    ///
    /// **대상은 최상위 본문 문단뿐이다** — 표 셀·글상자·각주 **안**의 개요
    /// 문단은 목록에 넣지 않는다 (호출자가 그 문단으로 이 함수를 부르지 않는다).
    /// 문서의 목차는 본문 흐름의 제목 계층이지 개체 안 텍스트가 아니고, 실측도
    /// 그쪽을 가리킨다: 헌법주석의 개요 문단 1,944개는 전부 최상위 본문 문단이고,
    /// `noori`의 개요 문단 4개는 전부 표/글상자 안이라 목차 항목이 아니다.
    /// 책갈피는 반대다 — 앵커라 어디에 놓이든 목적지이므로 본문 컨테이너를
    /// 재귀한다 (`collectBookmarks`).
    mutating func collectHeading(from paragraph: CoreHwp.HwpParagraph, page: Int) {
        guard items.count < Self.maximumItems else { return }
        guard let level = headingLevel(of: paragraph) else { return }
        let title = Self.normalizedTitle(of: paragraph)
        guard !title.isEmpty else { return }
        append(kind: .heading, title: title, level: level, page: page)
    }

    /// 1-기반 개요 수준 (해당 없으면 nil).
    mutating func headingLevel(of paragraph: CoreHwp.HwpParagraph) -> Int? {
        let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
        if let paraShape, paraShape.property1Info.headingTypeRawValue == 1 {
            // 저장값이 0-기반이므로 사람이 읽는 수준은 +1이다.
            return Int(paraShape.property1Info.headingLevelRawValue) + 1
        }
        return styleOutlineLevel(of: paragraph)
    }

    /// 스타일 이름 폴백 — `개요 N` / `Outline N`의 N (1-기반).
    /// 결과는 `styleLevelCache`에 메모한다 (nil 포함 — 근거는 그 선언부).
    mutating func styleOutlineLevel(of paragraph: CoreHwp.HwpParagraph) -> Int? {
        let styleId = paragraph.paraHeader.paraStyleId
        if let cached = styleLevelCache[styleId] {
            return cached
        }
        styleParseCount += 1
        let level = index.style(id: UInt32(styleId)).flatMap { style in
            Self.outlineLevel(inStyleName: style.styleLocalName)
                // 영문 이름 프로퍼티는 저장소의 오타를 그대로 쓴다 (public API라 유지).
                ?? Self.outlineLevel(inStyleName: style.styelEnglishName)
        }
        styleLevelCache[styleId] = level
        return level
    }

    /// `개요 3` · `Outline 3` · `개요3` → 3. 그 외에는 nil.
    /// 결과는 `HwpOutlineItem.maximumLevel`로 클램프된다 (아래 이유).
    ///
    /// 이름 규약의 근거는 `HwpIdMappings`의 빈 문서 기본 스타일 배열
    /// (`개요 1`~`개요 10` / `Outline 1`~`Outline 10`)이고, 실제 픽스처들도
    /// 자기 STYLE 레코드에 같은 이름을 갖는다.
    static func outlineLevel(inStyleName name: String) -> Int? {
        // 접두 판정과 자릿수 추출을 **같은 문자열**(소문자화본) 위에서 한다 —
        // 원본에서 자르면 대소문자 변환이 길이를 바꾸는 문자에서 어긋난다.
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        let prefixes = ["개요", "outline"]
        guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
            return nil
        }
        let digits = normalized
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        // 자릿수가 많아 `Int`에 안 들어가면 nil이라 트랩하지 않는다.
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let level = Int(digits), level >= 1
        else { return nil }
        return min(level, HwpOutlineItem.maximumLevel)
    }
}

// MARK: - 책갈피

private extension HwpOutlineCollector {
    /// 본문에 놓인 책갈피 컨트롤을 수집한다.
    ///
    /// **머리말/꼬리말은 뺀다** — 검색(`role == .body`)과 같은 스코프 규약이다.
    /// 쪽마다 다시 그려지는 크롬의 앵커는 "그 쪽으로 간다"의 목적지가 될 수
    /// 없고, 목록에 한 번만 실려도 어느 쪽을 가리키는지 정의되지 않는다.
    /// 각주·표 셀·글상자·중첩 표는 포함한다 (모델을 걷는 것이라 여러 쪽에
    /// 걸친 표에서도 셀은 한 번만 순회된다 — 중복 수집이 생기지 않는다).
    mutating func collectBookmarks(
        ctrls: [CoreHwp.HwpCtrlId],
        page: Int,
        depth: Int,
        tableDepth: Int,
        childParagraphs: ChildParagraphs
    ) {
        for ctrl in ctrls {
            if case let .bookmark(control) = ctrl {
                appendBookmark(control, page: page)
            }
            guard !Self.isPageChrome(ctrl) else { continue }
            // 표는 컨테이너 카운터가 아니라 **자체 한도**를 탄다 — 진단
            // (`walkUnsupported`)이 표를 컨테이너 가드에서 빼는 것과 같은
            // 술어여야 한다. 균일한 컨테이너 한도로 막으면 `HwpTableLayout`이
            // 자기 카운터로 조판한 depth 3 표의 셀 앵커가 **조용히** 빠진다
            // (렌더에서 빠진 것이 없으니 진단도 안 뜬다).
            let isTable = Self.isTable(ctrl)
            if isTable {
                guard tableDepth <= HwpTableLayout.maximumNestingDepth else { continue }
            } else {
                guard depth < Self.maximumContainerDepth else { continue }
            }
            for (nested, _) in childParagraphs(ctrl) {
                guard let nestedCtrls = nested.ctrlHeaderArray else { continue }
                // 표는 **컨테이너 카운터를 올리지 않는다**. 셀 안 개체는 흐름
                // 방출(`appendNestedControlBlocks`)이 아니라 `HwpTableLayout`이
                // 셀 콘텐츠로 그리므로 그 한도의 적용 대상이 아니다 — 함께
                // 올리면 표 3겹 안 글상자가 `depth == 3`에 걸려, 그려진 글상자의
                // 책갈피가 조용히 빠진다 (실측: 셀 페이로드에 textbox가 있는데
                // 목록은 비었다).
                collectBookmarks(
                    ctrls: nestedCtrls,
                    page: page,
                    depth: isTable ? depth : depth + 1,
                    tableDepth: isTable ? tableDepth + 1 : tableDepth,
                    childParagraphs: childParagraphs
                )
            }
        }
    }

    static func isPageChrome(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
        switch ctrl {
        case .header, .footer:
            true
        default:
            false
        }
    }

    static func isTable(_ ctrl: CoreHwp.HwpCtrlId) -> Bool {
        if case .table = ctrl {
            true
        } else {
            false
        }
    }

    mutating func appendBookmark(_ control: CoreHwp.HwpOtherControl, page: Int) {
        guard items.count < Self.maximumItems else { return }
        // 책갈피 이름도 제목과 **같은 천장**을 지난다 — `collapsedWhitespace`의
        // 상한은 Character 수라, 기반 문자 하나에 결합 문자가 수만 개 붙은 이름은
        // grapheme 하나로 세어져 128KB가 통째로 metadata에 상주한다.
        let name = Self.collapsedWhitespace(Self.ceilinged(control.bookmarkInfo?.name ?? ""))
        guard !name.isEmpty else { return }
        append(kind: .bookmark, title: name, level: nil, page: page)
    }
}

// MARK: - 공통

private extension HwpOutlineCollector {
    mutating func append(kind: HwpOutlineItem.Kind, title: String, level: Int?, page: Int) {
        items.append(HwpOutlineItem(
            kind: kind,
            title: title,
            level: level,
            // 조판 카운터가 0을 낼 일은 없지만 공개 값이라 하한을 고정한다.
            pageNumber: max(1, page),
            ordinal: items.count
        ))
    }

    /// 문단 → 목록에 보일 한 줄 평문.
    ///
    /// `HwpSelectionGeometry.strippingControlMarkers`를 쓸 수 없다 — 그쪽 입력은
    /// **이미 조판된 `NSAttributedString`의 부분 문자열**이라 `U+FFFC` 하나만
    /// 지우면 되지만, 수집 시점 입력은 `CoreHwp.HwpParagraph`다. Selection 타입에
    /// 얹힌 유틸을 Layout이 끌어 쓰는 모양도 곤란하다.
    ///
    /// 규칙: 탭(9)·줄바꿈(10)·문단 끝(13)·묶음 빈칸(30)·고정폭 빈칸(31)은 공백,
    /// 그 밖의 컨트롤 문자(inline/extended payload를 가진 개체·필드 마커)는 제거,
    /// 나머지 텍스트는 그대로. UTF-16 코드 단위로 모아 한 번에 문자열을 만들어
    /// 서로게이트 쌍이 쪼개지지 않게 한다.
    static func normalizedTitle(of paragraph: CoreHwp.HwpParagraph) -> String {
        var units: [UInt16] = []
        for character in paragraph.paraText?.charArray ?? [] {
            switch character.value {
            case 9, 10, 13, 30, 31:
                units.append(32)
            default:
                guard character.type == .char, character.value >= 32 else { continue }
                units.append(character.value)
            }
            // 안전판에 걸려도 **대리 쌍 중간에서는 끊지 않는다** — 끊으면
            // `String(decoding:)`이 U+FFFD로 복구해 "평문의 접두" 계약이 깨진다.
            // 짝을 채우고 다음 회차에 끊는다.
            if units.count >= Self.titleUnitCeiling,
               !UTF16.isLeadSurrogate(units[units.count - 1])
            {
                break
            }
        }
        return collapsedWhitespace(String(decoding: units, as: UTF16.self))
    }

    /// UTF-16 천장으로 자른다 — `unicodeScalars`로 모으므로 대리 쌍이 쪼개지지
    /// 않는다 (제목 수집이 `titleUnitCeiling`에서 하는 보장과 같다).
    static func ceilinged(_ text: String) -> String {
        guard text.utf16.count > titleUnitCeiling else { return text }
        var units = 0
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let width = UTF16.width(scalar)
            guard units + width <= titleUnitCeiling else { break }
            units += width
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// 연속 공백을 하나로 접고 양끝을 다듬은 뒤 상한으로 자른다.
    /// 자른 결과가 평문의 **접두**로 남도록 말줄임표를 붙이지 않는다.
    static func collapsedWhitespace(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > HwpOutlineItem.titleCharacterLimit else { return collapsed }
        return String(collapsed.prefix(HwpOutlineItem.titleCharacterLimit))
    }
}
