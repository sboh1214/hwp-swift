import CoreGraphics
import CoreText
import Foundation

/// 텍스트 선택의 지오메트리 해석기 — 점↔위치, 범위→하이라이트 rect,
/// 범위→일반 텍스트. 줄 배치는 렌더러와 같은 `HwpDrawnTextLayout`을 쓰므로
/// 하이라이트가 화면과 일치한다. 단위 목록·줄 배치는 페이지별 지연 계산
/// 후 캐시한다 (하이라이트는 가시 페이지에서만 질의된다).
public final class HwpSelectionGeometry {
    private let document: HwpDocument
    private var unitCache: [Int: [HwpTextUnit]] = [:]
    private var lineCache: [UnitKey: [HwpDrawnLine]] = [:]
    private var lineCacheOrder: [UnitKey] = []
    private let lineCacheLimit = 512

    private struct UnitKey: Hashable {
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

    private func drawnLines(pageIndex: Int, unitOrdinal: Int) -> [HwpDrawnLine] {
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

    private func highlightRect(in line: HwpDrawnLine, characterRange: NSRange) -> CGRect? {
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
        guard !selection.isCollapsed else { return "" }
        let (start, end) = selection.range
        var contributions: [Contribution] = []
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
                guard unitEnd > start, unitStart < end else { continue }
                let lower = max(start, unitStart).characterOffset
                let upper = unitStart >= start && unitEnd <= end
                    ? unit.attributedString.length
                    : min(end, unitEnd).characterOffset
                guard upper > lower else { continue }
                let slice = (unit.attributedString.string as NSString)
                    .substring(with: NSRange(location: lower, length: upper - lower))
                let text = Self.strippingControlMarkers(slice)
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
                contributions.append(Contribution(
                    text: text,
                    paragraphId: unit.paragraphId,
                    continuesNext: upper == unit.attributedString.length
                        && Self.isContinuedFragment(unit.attributedString)
                ))
            }
        }
        // 조각을 잇되 같은 원본 문단의 연속이면 개행을 넣지 않는다 (#9): 본문
        // 조각은 paraId 동일성으로 판정하고, '이어짐' 표식은 identity를 확인할 수
        // 없을 때(paraId 없음)만 폴백으로 쓴다 — 분할 표 행에선 다른 셀의 top
        // 조각이 연달아 오므로 표식이 문단 identity를 대신할 수 없다 (#7).
        var result = ""
        for (index, piece) in contributions.enumerated() {
            if index > 0 {
                let previous = contributions[index - 1]
                let sameParagraph =
                    (previous.paragraphId != nil && previous.paragraphId == piece.paragraphId)
                        || (previous.continuesNext
                            && (previous.paragraphId == nil || piece.paragraphId == nil))
                result += sameParagraph ? "" : "\n"
            }
            result += piece.text
        }
        return result
    }

    /// 복사 텍스트 조립용 조각 하나 (문단 연속 판정 메타 포함).
    private struct Contribution {
        let text: String
        let paragraphId: UInt32?
        /// 이 조각이 '이어짐' 표식을 달아 다음 조각이 같은 문단의 연속인지
        let continuesNext: Bool
    }

    private static func isContinuedFragment(_ attributed: NSAttributedString) -> Bool {
        guard attributed.length > 0 else { return false }
        return attributed.attribute(
            HwpAttributedStringKey.continuedParagraphFragment,
            at: attributed.length - 1,
            effectiveRange: nil
        ) != nil
    }

    private static func isRepeatedHeaderClone(_ attributed: NSAttributedString) -> Bool {
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
            let unit = nsText.character(at: offset)
            // 서로게이트(비-BMP 스칼라의 반쪽)는 유효 UnicodeScalar가 아니라
            // 공백으로 오분류된다 — 단어 문자로 취급해 이모지·비-BMP CJK 단어가
            // 끊기지 않게 한다 (#10).
            if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) {
                return true
            }
            let character = Character(UnicodeScalar(unit) ?? " ")
            return !character.isWhitespace && character != "\u{FFFC}"
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
