import CoreGraphics
import CoreText
import Foundation

/// 텍스트 선택의 지오메트리 해석기 — 점↔위치, 범위→하이라이트 rect,
/// 범위→일반 텍스트. 줄 배치는 렌더러와 같은 `HwpDrawnTextLayout`을 쓰므로
/// 하이라이트가 화면과 일치한다. 단위 목록·줄 배치는 페이지별 지연 계산
/// 후 캐시한다 (하이라이트는 가시 페이지에서만 질의된다).
public final class HwpSelectionGeometry {
    // 아래 다섯은 검색(#75)이 같은 캐시를 공유해야 해서 모듈 internal이다.
    // 캐시를 이중화하면 1,030쪽 문서에서 단위 전개가 두 벌 상주한다.
    // 공개 표면은 그대로다 — 어느 것도 public이 아니다.
    let document: HwpDocument
    var unitCache: [Int: [HwpTextUnit]] = [:]
    var lineCache: [UnitKey: [HwpDrawnLine]] = [:]
    var lineCacheOrder: [UnitKey] = []
    let lineCacheLimit = 512

    struct UnitKey: Hashable {
        let pageIndex: Int
        let unitOrdinal: Int
    }

    public init(document: HwpDocument) {
        self.document = document
    }

    // MARK: - 단위/줄 접근

    public func units(forPage pageIndex: Int) -> [HwpTextUnit] {
        if let cached = unitCache[pageIndex] {
            return cached
        }
        guard document.pages.indices.contains(pageIndex) else { return [] }
        let units = HwpSelectableText.units(in: document.pages[pageIndex])
        unitCache[pageIndex] = units
        return units
    }

    func drawnLines(pageIndex: Int, unitOrdinal: Int) -> [HwpDrawnLine] {
        let key = UnitKey(pageIndex: pageIndex, unitOrdinal: unitOrdinal)
        if let cached = lineCache[key] {
            return cached
        }
        let units = units(forPage: pageIndex)
        guard units.indices.contains(unitOrdinal) else { return [] }
        let unit = units[unitOrdinal]
        let lines = HwpDrawnTextLayout.lines(
            attributedString: unit.attributedString,
            origin: unit.rect.origin,
            lineWidth: max(unit.rect.width, 1)
        )
        lineCache[key] = lines
        lineCacheOrder.append(key)
        if lineCacheOrder.count > lineCacheLimit {
            let evicted = lineCacheOrder.removeFirst()
            lineCache[evicted] = nil
        }
        return lines
    }

    // MARK: - 점 → 위치

    /// 페이지 로컬 점에서 가장 가까운 텍스트 위치 (PDF식 관대한 스냅):
    /// 단위 rect 포함 → 줄 y 클램프 → 글리프 x 질의. 포함 단위가 없으면
    /// y가 겹치는 단위 중 수평 최근접 (다단), 그것도 없으면 y 최근접 단위.
    /// 페이지에 텍스트가 없으면 nil.
    public func position(nearest point: CGPoint, pageIndex: Int) -> HwpTextPosition? {
        let units = units(forPage: pageIndex)
        guard !units.isEmpty else { return nil }

        let ordinal = nearestUnitOrdinal(to: point, in: units)
        let unit = units[ordinal]
        let lines = drawnLines(pageIndex: pageIndex, unitOrdinal: ordinal)
        guard !lines.isEmpty else {
            return HwpTextPosition(
                pageIndex: pageIndex,
                blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex,
                characterOffset: 0
            )
        }

        // 줄: y로 클램프해 선택 (줄 사이 간격은 위쪽 줄에 귀속)
        let line = lines.min { lhs, rhs in
            distance(point.y, toRange: lhs.selectionRect.minY ... lhs.selectionRect.maxY)
                < distance(point.y, toRange: rhs.selectionRect.minY ... rhs.selectionRect.maxY)
        }!
        let offset = characterOffset(in: line, atX: point.x)
        return HwpTextPosition(
            pageIndex: pageIndex,
            blockIndex: unit.blockIndex,
            unitIndex: unit.unitIndex,
            characterOffset: offset
        )
    }

    private func nearestUnitOrdinal(to point: CGPoint, in units: [HwpTextUnit]) -> Int {
        // 1) 점을 포함하는 단위
        if let contained = units.lastIndex(where: { $0.rect.contains(point) }) {
            return contained
        }
        // 2) y 구간이 겹치는 단위 중 수평 최근접 (다단 대응)
        let overlapping = units.indices.filter {
            let rect = units[$0].rect
            return point.y >= rect.minY && point.y <= rect.maxY
        }
        if let nearest = overlapping.min(by: {
            distance(point.x, toRange: units[$0].rect.minX ... units[$0].rect.maxX)
                < distance(point.x, toRange: units[$1].rect.minX ... units[$1].rect.maxX)
        }) {
            return nearest
        }
        // 3) y 최근접 단위 (본문 위 = 첫 단위, 아래 = 마지막 단위로 자연 수렴)
        return units.indices.min(by: {
            distance(point.y, toRange: units[$0].rect.minY ... units[$0].rect.maxY)
                < distance(point.y, toRange: units[$1].rect.minY ... units[$1].rect.maxY)
        })!
    }

    private func distance(_ value: CGFloat, toRange range: ClosedRange<CGFloat>) -> CGFloat {
        if value < range.lowerBound {
            return range.lowerBound - value
        }
        if value > range.upperBound {
            return value - range.upperBound
        }
        return 0
    }

    /// 줄 안 x → 문자 오프셋. 줄 왼쪽 밖 = 줄 시작, 오른쪽 밖 = 줄 끝.
    /// 재조판된 CTLine에 질의하므로 화면 글리프 위치와 일치한다.
    private func characterOffset(in line: HwpDrawnLine, atX x: CGFloat) -> Int {
        let localX = x - line.baselineOrigin.x
        let start = line.stringRange.location
        let end = line.stringRange.location + line.stringRange.length
        // RTL 줄은 논리 시작이 시각적 오른쪽, 논리 끝이 왼쪽이다 — 줄 밖 x를
        // 스냅할 때 방향을 반영해야 아랍어 줄 너머 드래그가 반대 끝으로 튀지
        // 않는다 (#8).
        let rtl = Self.isRightToLeft(line.line)
        if localX <= 0 {
            return rtl ? end : start
        }
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
        if localX >= lineWidth {
            return rtl ? start : end
        }
        let index = CTLineGetStringIndexForPosition(line.line, CGPoint(x: localX, y: 0))
        guard index != kCFNotFound else { return start }
        // 재조판 라인은 substring (location 0) 기준일 수 있어 원 범위로 보정
        let ctRange = CTLineGetStringRange(line.line)
        return line.stringRange.location + (index - ctRange.location)
    }

    /// CTLine의 첫 글리프 run 방향이 RTL인지 (혼합 bidi 줄은 근사).
    private static func isRightToLeft(_ line: CTLine) -> Bool {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let first = runs.first
        else { return false }
        return CTRunGetStatus(first).contains(.rightToLeft)
    }

    // MARK: - 범위 → 하이라이트 rect

    /// 해당 페이지에 그릴 선택 하이라이트 rect들 (페이지 로컬 top-down).
    public func highlightRects(pageIndex: Int, selection: HwpTextSelection) -> [CGRect] {
        guard !selection.isCollapsed else { return [] }
        let (start, end) = selection.range
        guard pageIndex >= start.pageIndex, pageIndex <= end.pageIndex else { return [] }

        var rects: [CGRect] = []
        let units = units(forPage: pageIndex)
        for (ordinal, unit) in units.enumerated() {
            let unitStart = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex, characterOffset: 0
            )
            let unitEnd = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex,
                characterOffset: unit.attributedString.length
            )
            guard unitEnd > start, unitStart < end else { continue }
            let lower = max(start, unitStart).characterOffset
            let upper = unitStart >= start && unitEnd <= end
                ? unit.attributedString.length
                : min(end, unitEnd).characterOffset
            guard upper > lower else { continue }
            for line in drawnLines(pageIndex: pageIndex, unitOrdinal: ordinal) {
                if let rect = highlightRect(
                    in: line, characterRange: NSRange(
                        location: lower, length: upper - lower
                    )
                ) {
                    rects.append(rect)
                }
            }
        }
        return rects
    }

    func highlightRect(in line: HwpDrawnLine, characterRange: NSRange) -> CGRect? {
        let lineRange = line.stringRange
        let lower = max(characterRange.location, lineRange.location)
        let upper = min(
            characterRange.location + characterRange.length,
            lineRange.location + lineRange.length
        )
        guard upper > lower else { return nil }
        if lower == lineRange.location, upper == lineRange.location + lineRange.length {
            return line.selectionRect
        }
        let ctRange = CTLineGetStringRange(line.line)
        let startX = CTLineGetOffsetForStringIndex(
            line.line, lower - lineRange.location + ctRange.location, nil
        )
        let endX = CTLineGetOffsetForStringIndex(
            line.line, upper - lineRange.location + ctRange.location, nil
        )
        // RTL 줄은 논리 인덱스 증가에 따라 오프셋이 감소하므로 min/max로
        // 정규화한다 — 정규화 없이 endX > startX만 보면 RTL 선택이 사라진다 (#7).
        let minX = min(startX, endX)
        let maxX = max(startX, endX)
        guard maxX > minX else { return nil }
        return CGRect(
            x: line.baselineOrigin.x + minX,
            y: line.baselineOrigin.y - line.ascent,
            width: maxX - minX,
            height: line.ascent + line.descent
        )
    }

    // MARK: - 범위 → 텍스트

    /// 선택 범위의 일반 텍스트. 단위를 문서 순서로 이어붙이고 단위 경계에
    /// 줄바꿈을 넣는다 (문단 attributedString은 후행 \n을 갖지 않는다).
    /// 조판이 전혀 필요 없어 대용량 문서의 전체 선택도 빠르다.
    public func plainText(for selection: HwpTextSelection) -> String {
        let pieces = fragments(for: selection)
        var result = ""
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                result += Self.joinsWithPrevious(pieces[index - 1], piece) ? "" : "\n"
            }
            result += Self.strippingControlMarkers(
                Self.droppingEmptyLineAnchor(piece.attributedText).string
            )
        }
        return result
    }

    /// 복사 조립용 조각 하나 (문단 연속 판정 메타 포함). 조각은 마커(U+FFFC)를
    /// 아직 품고 있다 — 제거는 각 조립 경로 몫이다.
    struct Fragment {
        /// 선택 구간으로 자른 attributed 부분열 (조판 속성 그대로)
        let attributedText: NSAttributedString
        let paragraphId: UInt32?
        /// 본문 문단의 위치 열쇠 — 있으면 이것만이 "같은 문단"의 근거다 (#145)
        let paragraphKey: HwpParagraphKey?
        /// 이 조각이 '이어짐' 표식을 달아 다음 조각이 같은 문단의 연속인지
        let continuesNext: Bool
    }

    /// 선택 범위의 기여 조각 수집 — 평문(`plainText`)·속성(`attributedText`) 두
    /// 조립 경로가 같은 배열을 받는다. 각자 수집하면 dedup·연속 정책이 조용히
    /// 갈라진다 (#118).
    func fragments(for selection: HwpTextSelection) -> [Fragment] {
        guard !selection.isCollapsed else { return [] }
        let (start, end) = selection.range
        var fragments: [Fragment] = []
        // 이미 복사에 기여한 문단 식별자 — 반복 제목 행 클론을 출처 identity로
        // 중복 제거한다 (텍스트 일치가 아니라 paraId — 같은 텍스트의 데이터 셀을
        // 오탐하지 않음, #8). 원본 헤더와 클론은 같은 paraId를 공유한다.
        var contributedParagraphIds = Set<UInt32>()
        for pageIndex in start.pageIndex ... end.pageIndex {
            for unit in units(forPage: pageIndex) {
                let unitStart = HwpTextPosition(
                    pageIndex: pageIndex, blockIndex: unit.blockIndex,
                    unitIndex: unit.unitIndex, characterOffset: 0
                )
                let unitEnd = HwpTextPosition(
                    pageIndex: pageIndex, blockIndex: unit.blockIndex,
                    unitIndex: unit.unitIndex,
                    characterOffset: unit.attributedString.length
                )
                // 빈 문단(앵커 하나뿐인 단위, #145)은 캐럿 자리가 하나라 (P,0)과
                // (P,1)이 같은 자리다 — 선택이 닿기만 하면 그 줄을 통째로 싣는다.
                // 비어 있지 않은 단위의 배타 규칙(끝점이 단위 시작이면 제외)을 그대로
                // 두면 'A에서 빈 줄까지'가 A의 종결자를, '빈 줄에서 B까지'가 빈 줄을
                // 잃는다. 조각의 글자(앵커)는 조립이 뗀다 (`droppingEmptyLineAnchor`).
                let isEmptyParagraph = HwpTextRunBuilder.isEmptyParagraphAnchor(
                    unit.attributedString
                )
                if isEmptyParagraph {
                    guard unitEnd >= start, unitStart <= end else { continue }
                } else {
                    guard unitEnd > start, unitStart < end else { continue }
                }
                let lower = isEmptyParagraph ? 0 : max(start, unitStart).characterOffset
                let upper = isEmptyParagraph || (unitStart >= start && unitEnd <= end)
                    ? unit.attributedString.length
                    : min(end, unitEnd).characterOffset
                guard upper > lower else { continue }
                // 반복 제목 행 클론은 같은 출처(paraId)가 이미 기여했을 때만
                // 제외한다 — 원본이 선택 밖(뒷페이지 클론만 선택)이면 그 클론을
                // 넣어야 복사가 비지 않는다. 하이라이트는 항상 남는다 (#8, #21 보정).
                if Self.isRepeatedHeaderClone(unit.attributedString),
                   let paragraphId = unit.paragraphId,
                   contributedParagraphIds.contains(paragraphId)
                {
                    continue
                }
                if let paragraphId = unit.paragraphId {
                    contributedParagraphIds.insert(paragraphId)
                }
                fragments.append(Fragment(
                    attributedText: unit.attributedString.attributedSubstring(
                        from: NSRange(location: lower, length: upper - lower)
                    ),
                    paragraphId: unit.paragraphId,
                    paragraphKey: unit.paragraphKey,
                    continuesNext: upper == unit.attributedString.length
                        && Self.isContinuedFragment(unit.attributedString)
                ))
            }
        }
        return fragments
    }

    /// 앞 조각과 개행 없이 이어지는가 (#9, #145): 본문 조각은 **위치 열쇠**
    /// 동일성으로 판정한다 — 열/쪽에 걸친 조각·다단 재분배 블록이 모두 같은
    /// 열쇠를 물려받는다. 열쇠가 없는 조각(표 셀·글상자·각주 문단)은 '이어짐'
    /// 표식이 있을 때만 잇되, 분할 표 행에선 다른 셀의 top 조각이 연달아 오므로
    /// paraId가 있고 서로 다르면 표식이 있어도 잇지 않는다 (#7).
    ///
    /// 종전의 "같은 paraId면 같은 문단" 갈래는 뺐다 — 한글.app 저장본은 paraId가
    /// 문단마다 고유하지 않아(noori HWP·HWPX 65문단 중 고유 값 0·0x80000000 둘)
    /// 서로 다른 본문 문단·같은 셀의 문단들이 개행 없이 붙었다. 그 값은 반복
    /// 머리행 클론 dedup의 출처 식별에만 남는다.
    static func joinsWithPrevious(_ previous: Fragment, _ piece: Fragment) -> Bool {
        if let previousKey = previous.paragraphKey, let key = piece.paragraphKey {
            return previousKey == key
        }
        return previous.continuesNext
            && (previous.paragraphId == nil || piece.paragraphId == nil
                || previous.paragraphId == piece.paragraphId)
    }

    private static func isContinuedFragment(_ attributed: NSAttributedString) -> Bool {
        guard attributed.length > 0 else { return false }
        return attributed.attribute(
            HwpAttributedStringKey.continuedParagraphFragment,
            at: attributed.length - 1,
            effectiveRange: nil
        ) != nil
    }

    /// 검색(#75)의 목록 dedup이 같은 판정을 재사용한다 — 각자
    /// `HwpAttributedStringKey.repeatedTableHeaderClone`을 읽으면 정책이 갈라진다.
    static func isRepeatedHeaderClone(_ attributed: NSAttributedString) -> Bool {
        guard attributed.length > 0 else { return false }
        return attributed.attribute(
            HwpAttributedStringKey.repeatedTableHeaderClone,
            at: 0,
            effectiveRange: nil
        ) != nil
    }

    /// U+FFFC 개체 자리 표시 마커 제거
    static func strippingControlMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// 조판 전용 빈 줄 앵커를 뗀다 (`HwpAttributedStringKey.emptyLineAnchor`).
    ///
    /// 앵커는 한 줄 끝(10)으로 끝난 문단의 마지막 빈 줄을 CoreText가 만들게
    /// 하려고 조판이 **합성한** 빈칸이라 원문에 없다 — 복사에 실리면 안 된다.
    /// 글자만으로는 사용자가 입력한 빈칸과 구별할 수 없으므로 표식으로 판정한다.
    /// 앵커는 언제나 문단의 마지막 문자라 조각에 실렸다면 그 조각의 끝이다 —
    /// 전수 스캔 없이 마지막 글자만 본다 (마커 제거의 선형 규약과 같은 이유).
    static func droppingEmptyLineAnchor(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0,
              attributed.attribute(
                  HwpAttributedStringKey.emptyLineAnchor,
                  at: attributed.length - 1,
                  effectiveRange: nil
              ) != nil
        else { return attributed }
        return attributed.attributedSubstring(
            from: NSRange(location: 0, length: attributed.length - 1)
        )
    }

    // MARK: - 전체 선택

    /// 문서 전체 선택 범위: 첫 텍스트 단위 시작 ~ 마지막 텍스트 단위 끝.
    /// 앞뒤에서 각각 최근접 텍스트 페이지까지만 스캔한다 — units는 페이지별
    /// 캐시라 1,030쪽 문서에서도 빠르다. 텍스트가 전혀 없으면 nil.
    /// (이후 `plainText(for:)`로 전체를 복사하는 비용은 당연히 O(문서)다.)
    public func documentSelection() -> HwpTextSelection? {
        var first: HwpTextPosition?
        for pageIndex in document.pages.indices {
            guard let unit = units(forPage: pageIndex).first else { continue }
            first = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex, characterOffset: 0
            )
            break
        }
        var last: HwpTextPosition?
        for pageIndex in document.pages.indices.reversed() {
            guard let unit = units(forPage: pageIndex).last else { continue }
            last = HwpTextPosition(
                pageIndex: pageIndex, blockIndex: unit.blockIndex,
                unitIndex: unit.unitIndex,
                characterOffset: unit.attributedString.length
            )
            break
        }
        guard let first, let last, first < last else { return nil }
        return HwpTextSelection(anchor: first, focus: last)
    }

    // MARK: - 단어 선택

    /// 더블클릭/롱프레스용 단어 범위
    public func wordRange(at position: HwpTextPosition) -> HwpTextSelection? {
        let units = units(forPage: position.pageIndex)
        guard let unit = units.first(where: {
            $0.blockIndex == position.blockIndex && $0.unitIndex == position.unitIndex
        }) else { return nil }
        let text = unit.attributedString.string
        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        let clamped = min(max(position.characterOffset, 0), nsText.length - 1)
        var start = clamped
        var end = clamped
        func isWordCharacter(_ offset: Int) -> Bool {
            Self.isWordCharacter(in: nsText, at: offset)
        }
        guard isWordCharacter(clamped) else { return nil }
        while start > 0, isWordCharacter(start - 1) {
            start -= 1
        }
        while end < nsText.length, isWordCharacter(end) {
            end += 1
        }
        return HwpTextSelection(
            anchor: HwpTextPosition(
                pageIndex: position.pageIndex, blockIndex: position.blockIndex,
                unitIndex: position.unitIndex, characterOffset: start
            ),
            focus: HwpTextPosition(
                pageIndex: position.pageIndex, blockIndex: position.blockIndex,
                unitIndex: position.unitIndex, characterOffset: end
            )
        )
    }
}

extension HwpSelectionGeometry {
    /// 단어 문자 판정. 비-BMP 스칼라는 서로게이트 쌍을 결합해 완전한
    /// 스칼라로 판정한다 — 반쪽을 무조건 단어 문자로 두면 이모지가 기호
    /// 경계 (R33 #3)를 우회한다 (R34 #3). 비-BMP CJK는 결합 후에도 단어
    /// 문자다 (#10 의도 보존). 쌍이 깨진 고아 반쪽만 단어 문자로 관대 처리.
    static func isWordCharacter(in text: NSString, at offset: Int) -> Bool {
        let unit = text.character(at: offset)
        let scalar: UnicodeScalar
        if UTF16.isLeadSurrogate(unit), offset + 1 < text.length,
           UTF16.isTrailSurrogate(text.character(at: offset + 1))
        {
            scalar = pairedScalar(lead: unit, trail: text.character(at: offset + 1))
        } else if UTF16.isTrailSurrogate(unit), offset > 0,
                  UTF16.isLeadSurrogate(text.character(at: offset - 1))
        {
            scalar = pairedScalar(lead: text.character(at: offset - 1), trail: unit)
        } else if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) {
            return true
        } else {
            scalar = UnicodeScalar(unit) ?? " "
        }
        let character = Character(scalar)
        // 구두점/기호는 단어 경계다 (한글.app: 더블클릭이 쉼표에서 멈춘다)
        // — 아포스트로피 포함이라 don't는 갈라진다 (허용 근사, R33 #3)
        if character.isPunctuation || character.isSymbol {
            return false
        }
        return !character.isWhitespace && character != "\u{FFFC}"
    }

    /// UTF-16 서로게이트 쌍 → 스칼라 (0x10000 + (lead−0xD800)<<10 + (trail−0xDC00))
    private static func pairedScalar(lead: unichar, trail: unichar) -> UnicodeScalar {
        let value = 0x10000
            + ((UInt32(lead) - 0xD800) << 10)
            + (UInt32(trail) - 0xDC00)
        return UnicodeScalar(value) ?? " "
    }
}
