import Foundation

/// 문서 텍스트 스캐너 — 상태가 없고 조판(CoreText)을 전혀 건드리지 않는다.
///
/// **매칭 좌표계.** 매칭은 `HwpTextUnit.attributedString.string`의 **UTF-16
/// 오프셋** 위에서 한다. 그것이 `HwpTextPosition.characterOffset`의 정의이기
/// 때문이다. `HwpSelectionGeometry.plainText(for:)` 결과 위에서 매칭하면
/// U+FFFC 제거와 같은 문단 조각 결합 때문에 오프셋이 하이라이트 좌표계와
/// 어긋난다 — 그 경로는 쓰지 않는다.
///
/// **검색 범위.** `block.role == .body`인 블록의 텍스트뿐이다. 머리말·꼬리말·
/// 쪽 번호는 빠지고, 메모(댓글) 풍선은 role 필터 이전에 구조적으로 빠진다
/// (`HwpSelectableText.units(in:)`은 `page.blocks`만 도는데 메모는
/// `HwpPage.memoPanel`에 따로 산다). 각주·미주·표 셀·글상자·중첩 표 텍스트는
/// **포함된다**. 각주 자동 번호는 조판 단계에서 `"1)"` 같은 실제 문자로
/// 치환돼 들어오므로 그 문자열로 검색하면 매치되는 것이 정상이다.
public enum HwpTextSearcher {
    /// 이미 전개된 단위를 스캔한다.
    ///
    /// `HwpSelectionGeometry.units(forPage:)`의 캐시를 그대로 먹이는 경로라
    /// 단위 전개가 이중화되지 않는다 — 뷰와 함께 쓰는 상시 경로가 이것이다.
    /// `[HwpTextUnit]`은 Sendable이 아니므로 호출자 격리 안에서만 쓴다.
    ///
    /// - Parameters:
    ///   - matchLimit: 0이면 무제한. 상한에 닿으면 즉시 반환한다(조기 종료).
    ///   - snippetPadding: 0이면 스니펫을 수집하지 않는다.
    public static func matches(
        in units: [HwpTextUnit],
        pageIndex: Int,
        query: HwpSearchQuery,
        matchLimit: Int = 0,
        snippetPadding: Int = 0
    ) -> [HwpSearchMatch] {
        guard !query.isEmpty else { return [] }
        let budget = ScanBudget(matchLimit: matchLimit, snippetPadding: snippetPadding)
        var results: [HwpSearchMatch] = []
        for unit in units {
            appendMatches(
                in: unit, pageIndex: pageIndex, query: query,
                budget: budget, into: &results
            )
            if budget.isFull(results.count) {
                break
            }
        }
        return results
    }

    /// 스캔 예산 — 결과의 **의미**를 바꾸지 않고 비용만 자른다.
    struct ScanBudget {
        /// 0이면 무제한.
        let matchLimit: Int
        /// 0이면 스니펫을 수집하지 않는다.
        let snippetPadding: Int

        func isFull(_ count: Int) -> Bool {
            matchLimit > 0 && count >= matchLimit
        }
    }

    /// 페이지를 직접 전개해 스캔한다.
    ///
    /// `HwpPage`와 `HwpSearchMatch`가 모두 Sendable이고 이 함수가 nonisolated
    /// 순수 함수라 **오프메인 호출이 타입상 가능하다** — 배치 인덱싱이나 CLI가
    /// 이 경로를 쓴다. 대가는 지오메트리의 단위 캐시를 공유하지 못해 전개가
    /// 이중화된다는 것이다.
    public static func matches(
        in page: HwpPage,
        pageIndex: Int,
        query: HwpSearchQuery,
        matchLimit: Int = 0,
        snippetPadding: Int = 0
    ) -> [HwpSearchMatch] {
        matches(
            in: HwpSelectableText.units(in: page),
            pageIndex: pageIndex,
            query: query,
            matchLimit: matchLimit,
            snippetPadding: snippetPadding
        )
    }

    /// 목록 표시용 dedup — 쪽에 걸친 표의 반복 머리행 클론을 걷어낸다.
    ///
    /// 판정은 매치가 아니라 **단위** 단위다. 매치 하나씩 판정하면 같은 클론
    /// 행 안의 두 번째 매치가 잘못 사라진다 (첫 매치가 paraId를 세트에 넣고
    /// 바로 다음 매치가 거기 걸린다).
    ///
    /// '먼저 나온 것을 살린다'는 `plainText(for:)`의 규약과 같은 의미다 —
    /// 원본이 아직 안 나왔으면 클론을 남긴다. 하이라이트에는 이 함수를
    /// 통과시키지 않는다: 화면에는 클론도 칠해야 한다.
    ///
    /// 입력은 문서 순서로 정렬돼 있어야 한다 (스캐너 출력이 그렇다).
    public static func deduplicatingRepeatedTableHeaders(
        _ matches: [HwpSearchMatch]
    ) -> [HwpSearchMatch] {
        var contributedParagraphIds = Set<UInt32>()
        var results: [HwpSearchMatch] = []
        appendDeduplicating(
            matches, into: &results, contributedParagraphIds: &contributedParagraphIds
        )
        return results
    }

    /// 위 dedup 의 증분판 — 스캔이 페이지마다 부른다.
    ///
    /// 단위는 쪽 경계를 넘지 않으므로 (`unitKey` 에 pageIndex 가 들어 있다)
    /// 페이지 단위로 나눠 먹여도 한 번에 훑은 것과 결과가 같다. 매치 상한을
    /// **목록 기준**으로 세려면 스캔이 이 결과를 손에 들고 있어야 한다 —
    /// 클론까지 세면 나중에 버려질 항목에 예산을 쓴다.
    static func appendDeduplicating(
        _ matches: [HwpSearchMatch],
        into results: inout [HwpSearchMatch],
        contributedParagraphIds: inout Set<UInt32>
    ) {
        var index = matches.startIndex
        while index < matches.endIndex {
            let key = matches[index].unitKey
            let groupStart = index
            while index < matches.endIndex, matches[index].unitKey == key {
                index += 1
            }
            let group = matches[groupStart ..< index]
            guard let first = group.first else { continue }
            if first.isRepeatedTableHeaderClone,
               let paragraphId = first.paragraphId,
               contributedParagraphIds.contains(paragraphId)
            {
                continue
            }
            if let paragraphId = first.paragraphId {
                contributedParagraphIds.insert(paragraphId)
            }
            results.append(contentsOf: group)
        }
    }

    // MARK: - 단위 스캔

    private static func appendMatches(
        in unit: HwpTextUnit,
        pageIndex: Int,
        query: HwpSearchQuery,
        budget: ScanBudget,
        into results: inout [HwpSearchMatch]
    ) {
        let text = unit.attributedString.string as NSString
        // 빈 문단 앵커(빈칸 1자, #145)는 원문에 없는 글자라 " " 질의에 걸리면 안 된다.
        guard text.length > 0,
              !HwpTextRunBuilder.isEmptyParagraphAnchor(unit.attributedString)
        else { return }
        let options = query.compareOptions
        let isClone = HwpSelectionGeometry.isRepeatedHeaderClone(unit.attributedString)
        var cursor = 0

        while cursor < text.length {
            let found = text.range(
                of: query.text,
                options: options,
                range: NSRange(location: cursor, length: text.length - cursor)
            )
            guard found.location != NSNotFound, found.length > 0 else { return }
            // 커서는 반환된 range 기준으로 넘긴다 — 정규 동치 비교에서는
            // found.length가 질의의 UTF-16 길이와 다를 수 있다.
            cursor = found.location + found.length

            if !query.options.contains(.wholeWord) || isWholeWord(found, in: text) {
                results.append(HwpSearchMatch(
                    selection: selection(for: found, in: unit, pageIndex: pageIndex),
                    paragraphId: unit.paragraphId,
                    isRepeatedTableHeaderClone: isClone,
                    snippet: budget.snippetPadding > 0
                        ? snippet(for: found, in: text, padding: budget.snippetPadding)
                        : nil
                ))
                if budget.isFull(results.count) {
                    return
                }
            }
        }
    }

    private static func selection(
        for range: NSRange, in unit: HwpTextUnit, pageIndex: Int
    ) -> HwpTextSelection {
        HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex, characterOffset: range.location
            ),
            focus: HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex,
                characterOffset: range.location + range.length
            )
        )
    }

    /// 매치 앞뒤가 단어 문자가 아닌가. 문자열 경계는 단어 경계로 본다.
    private static func isWholeWord(_ range: NSRange, in text: NSString) -> Bool {
        if range.location > 0,
           HwpSelectionGeometry.isWordCharacter(in: text, at: range.location - 1)
        {
            return false
        }
        let after = range.location + range.length
        if after < text.length,
           HwpSelectionGeometry.isWordCharacter(in: text, at: after)
        {
            return false
        }
        return true
    }

    /// 매치 주변을 `padding`만큼 떼어 온다. 잘라 내는 지점은 결합 문자
    /// 시퀀스 경계로 넓힌다 — UTF-16 오프셋을 그대로 자르면 서로게이트 쌍이나
    /// 결합 한글이 반쪽으로 잘린다.
    private static func snippet(
        for range: NSRange, in text: NSString, padding: Int
    ) -> HwpSearchSnippet {
        // 클램프가 산술보다 **먼저**다. `padding` 은 공개 인자라 `Int.max` 가
        // 들어오는데, 그러면 `min` 이 자르기 전에 덧셈이 터진다. 문자열 길이를
        // 넘는 여백은 어차피 문자열 전체와 같다.
        let clamped = max(0, min(padding, text.length))
        let lower = max(0, range.location - clamped)
        let upper = min(text.length, range.location + range.length + clamped)
        let safe = text.rangeOfComposedCharacterSequences(
            for: NSRange(location: lower, length: upper - lower)
        )
        return HwpSearchSnippet(
            text: text.substring(with: safe),
            matchRange: (range.location - safe.location)
                ..< (range.location - safe.location + range.length)
        )
    }
}
