import CoreGraphics
import CoreHwp
import Foundation

// 각주 예약 높이 — 배치(`HwpFootnoteLayout.place`의 스택 산식)와 **동형**이어야 한다.
// 예약이 작으면 각주 스택이 본문을 덮고, 크면 한글에 없는 쪽 절단이 생긴다.
// `HwpFootnoteCoordinator.swift`가 SwiftLint file_length 상한(700줄)에 닿아 갈라 뒀다.

// MARK: - 예약/측정

//
// 예약은 **배치와 동형**이어야 한다 (`HwpFootnoteLayout.place`의 스택 산식) —
// 예약이 작으면 각주 스택이 본문을 덮고, 크면 한글에 없는 페이지 절단이 생긴다.
// 그 동형성을 한 곳에서 읽을 수 있도록 확장으로 묶었다.

extension HwpFootnoteCoordinator {
    /// 각주 예약 기하 — 배치 (HwpFootnoteLayout.place)와 같은 divider 소스
    func footnoteReservationMetrics(
        environment: Environment
    ) -> HwpFootnoteLayout.ReservationMetrics {
        footnoteLayout.reservationMetrics(
            footnoteShape: environment.footnoteShape,
            contentWidth: environment.contentWidth
        )
    }

    /// 이월된 각주 입력들이 새 페이지에서 예약할 높이 — 배치 (place)와
    /// 동형: Σ 높이 + 노트 경계마다 간격 + 구분선 오버헤드.
    ///
    /// **다음 쪽에 실릴 조각까지만** 더한다 (#165 리뷰): 분할 지점이 여러 쪽에 걸친 각주의 남은
    /// 전부를 더하면 예약이 쪽 높이를 넘어 `effectiveContentHeight`가 1pt로 무너지고, 캐시
    /// 없는 흐름 문단·표가 자리가 남아도 다음 쪽으로 밀린다 — 배치(`stackPlan`)는 그 쪽에
    /// 첫 분할 지점까지의 앞 조각만 싣고 그 뒤 각주는 넘기므로, 예약도 그 조각에서 멈춘다
    /// (한글도 그 쪽에 그 조각만 놓았다 — 분할 지점이 곧 한글의 쪽 경계다). 분할 지점은
    /// `splitPoint`와 **같은 둘**이다: 문단 안의 세로 위치 리셋, 그리고 앞 문단의 마지막 줄보다
    /// 위에서 시작하는 뒤 문단 (그 문단부터 통째로 다음 쪽).
    mutating func reservedFootnoteHeight(
        for inputs: HwpFootnoteLayout.PendingNotes,
        environment: Environment,
        upTo limit: CGFloat = .infinity
    ) -> CGFloat {
        guard !inputs.isEmpty else { return 0 }
        let metrics = footnoteReservationMetrics(environment: environment)
        var total = metrics.separatorOverhead
        // 개체 판정은 **각주 단위** (#165 리뷰) — 배치와 같은 범위를 본다. 수집 시점의 사실
        // (`Input.noteFacts`)이 있으면 그것이고, 없으면 각주가 바뀌는 자리에서 그 이웃만 훑는다
        // — 전부를 먼저 훑으면 `limit`에 멈추는 뜻이 없다.
        var noteCarriesObjects = false
        // 같은 각주 안 앞 문단의 남은 마지막 줄 전진량 끝 — 뒤 문단이 그보다 위에서 시작하면
        // 문단 경계가 쪽 경계다 (`splitPoint`와 같은 판정). 캐시 없는 문단은 비교를 끊는다.
        var previousBottom: Int?
        var index = inputs.startIndex
        while index < inputs.endIndex, total <= limit {
            let input = inputs[index]
            let next = inputs.index(after: index)
            let startsNote = index == inputs.startIndex || inputs[inputs.index(before: index)].noteId != input.noteId
            if startsNote {
                if index > inputs.startIndex {
                    total += metrics.spacingBetweenNotes
                }
                noteCarriesObjects = input.noteFacts?.carriesObjects
                    ?? Self.noteCarriesObjects(in: inputs, from: index)
                previousBottom = nil
            }
            // 배치(`HwpFootnoteLayout.measure`)가 `input.sizeResolver`를 쓰므로
            // 재예약도 같은 값으로 재야 한다 — 현재 environment로 재면 그 사이
            // 단·구역 기하가 바뀐 문서에서 예약과 배치가 갈린다 (R45 #1).
            // 이어지는 조각(#165)은 앞 쪽에 실린 줄 뒤만 잰다 — 배치와 같은 산식.
            var noteEnvironment = input.sizeResolver.map(environment.withSizeResolver)
                ?? environment
            if let measured = input.measuredShape {
                noteEnvironment = noteEnvironment.withFootnoteShape(measured.footnoteShape)
            }
            // 개체를 담은 각주는 나뉘지 않는다 — 그 밖의 문단은 남은 줄의 첫 분할 지점까지만.
            let cacheLines = noteCarriesObjects ? nil
                : input.sourceLayout?.cacheLines ?? HwpFootnoteCacheLines.lines(of: input.paragraph)
            var firstBreak: Int?
            if let lines = cacheLines {
                let start = min(input.placedLineCount, lines.count)
                if start < lines.count {
                    if let previousBottom, !startsNote, lines[start].location < previousBottom {
                        // 이 문단부터 다음 쪽이다 (#165 리뷰) — 앞 문단까지만 예약한다.
                        break
                    }
                    firstBreak = HwpFootnoteCacheLines.firstPageBreak(in: lines, after: start)
                    previousBottom = lines[lines.count - 1].spacedBottom
                }
            } else {
                previousBottom = nil
            }
            let isNoteEnd = next == inputs.endIndex || inputs[next].noteId != input.noteId
            total += measuredFootnoteHeight(
                of: input.paragraph,
                number: input.number,
                environment: noteEnvironment,
                numbering: input.numbering,
                isNoteEnd: isNoteEnd || firstBreak != nil,
                placedLineCount: input.placedLineCount,
                noteCarriesObjects: noteCarriesObjects,
                // 이월 입력이 나른 원본 조판(줄 캐시·남은 높이 누적표)을 그대로 쓴다 (#165
                // 리뷰) — 쪽마다 줄 캐시를 다시 만들고 남은 줄을 다 더하면 이월이 길게
                // 이어지는 문단에서 쪽 수 × 줄 수의 일이다.
                sourceLayout: input.sourceLayout,
                lineLimit: firstBreak.map { $0 - input.placedLineCount }
            )
            if firstBreak != nil {
                break
            }
            index = next
        }
        return total
    }

    /// `start`에서 시작하는 각주의 개체 유무 — 수집 시점 사실이 없는 입력(공개 API)의 폴백.
    private static func noteCarriesObjects(
        in inputs: HwpFootnoteLayout.PendingNotes, from start: Int
    ) -> Bool {
        var probe = start
        while probe < inputs.endIndex, inputs[probe].noteId == inputs[start].noteId {
            if HwpParagraphObjectCollector.hasCollectibleObject(
                in: inputs[probe].paragraph, collectsTextboxes: true, collectsTables: true
            ) {
                return true
            }
            probe = inputs.index(after: probe)
        }
        return false
    }

    /// 이 문단이 페이지에 추가될 때 각주 영역이 요구할 높이 (커밋 전 예측용).
    /// 컨테이너 (표 셀 등) 안 각주도 포함하며, 미주는 페이지 하단 영역을
    /// 쓰지 않으므로 계산에서 제외한다.
    /// numbering: 이 문단의 번호 열쇠 (#158) — 예약이 수집과 같은 라벨로 재야 한다.
    mutating func anticipatedFootnoteHeight(
        for paragraph: CoreHwp.HwpParagraph,
        environment: Environment,
        childParagraphs: ChildParagraphs,
        numbering: HwpNumberingScope? = nil
    ) -> CGFloat {
        // collectFootnotes가 부여할 번호와 같은 순서의 미리보기 카운터
        var preview = footnoteCounter
        let body = anticipatedFootnoteBodyHeight(
            for: paragraph,
            preview: &preview,
            environment: environment,
            childParagraphs: childParagraphs,
            numbering: numbering
        )
        guard body > 0 else { return 0 }
        // 배치와 동형: 새 노트 수만큼의 경계 간격 (페이지 첫 노트는 경계가
        // 하나 적다) + 페이지 첫 각주면 구분선 오버헤드.
        let metrics = footnoteReservationMetrics(environment: environment)
        let newNotes = preview - footnoteCounter
        let boundaries = max(0, pendingFootnotes.isEmpty ? newNotes - 1 : newNotes)
        return body + metrics.spacingBetweenNotes * CGFloat(boundaries)
            + (pendingFootnotes.isEmpty ? metrics.separatorOverhead : 0)
    }

    /// 주어진 grid 행 범위의 셀 각주가 예약할 높이 — pending/reserved/counter를
    /// 바꾸지 않고 측정만 한다 (표 세그먼트 크기 산정 전 예약용, collect와 동형
    /// 필터). 셀 각주가 없으면 0이라 표 배치가 기존과 동일하다.
    mutating func anticipatedTableCellFootnoteHeight(
        cellsByRow: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]],
        rows: ClosedRange<Int>,
        environment: Environment,
        childParagraphs: ChildParagraphs,
        numbering: HwpNumberingScope.TableCells? = nil
    ) -> CGFloat {
        var preview = footnoteCounter
        var body: CGFloat = 0
        for (cellIndex, cell) in Self.cellsInRows(cellsByRow, rows: rows) {
            for (paragraphIndex, paragraph) in cell.paragraphArray.enumerated() {
                body += anticipatedFootnoteBodyHeight(
                    for: paragraph,
                    preview: &preview,
                    environment: environment,
                    childParagraphs: childParagraphs,
                    numbering: numbering?.paragraph(
                        cellIndex: cellIndex, paragraphIndex: paragraphIndex
                    )
                )
            }
        }
        guard body > 0 else { return 0 }
        let metrics = footnoteReservationMetrics(environment: environment)
        let newNotes = preview - footnoteCounter
        let boundaries = max(0, pendingFootnotes.isEmpty ? newNotes - 1 : newNotes)
        return body + metrics.spacingBetweenNotes * CGFloat(boundaries)
            + (pendingFootnotes.isEmpty ? metrics.separatorOverhead : 0)
    }

    private mutating func anticipatedFootnoteBodyHeight(
        for paragraph: CoreHwp.HwpParagraph,
        depth: Int = 0,
        preview: inout Int,
        environment: Environment,
        childParagraphs: ChildParagraphs,
        numbering: HwpNumberingScope?
    ) -> CGFloat {
        guard let ctrls = paragraph.ctrlHeaderArray else { return 0 }
        var total: CGFloat = 0
        for (ordinal, ctrl) in ctrls.enumerated() {
            let container = numbering?.container(controlIndex: ordinal)
            if case let .footnote(list) = ctrl {
                let paragraphs = list.listArray.flatMap(\.paragraphArray)
                if !paragraphs.isEmpty {
                    let number = preview
                    preview += 1
                    let noteCarriesObjects = paragraphs.contains {
                        HwpParagraphObjectCollector.hasCollectibleObject(
                            in: $0, collectsTextboxes: true, collectsTables: true
                        )
                    }
                    // 같은 컨트롤의 문단은 간격 없이 이어진다 — 노트 경계
                    // 간격은 anticipatedFootnoteHeight가 노트 수로 계산한다
                    for (paragraphIndex, noteParagraph) in paragraphs.enumerated() {
                        total += measuredFootnoteHeight(
                            of: noteParagraph,
                            number: number,
                            environment: environment,
                            numbering: container?.paragraph(childIndex: paragraphIndex),
                            isNoteEnd: paragraphIndex == paragraphs.count - 1,
                            noteCarriesObjects: noteCarriesObjects
                        )
                    }
                }
            }
            guard depth < 3 else { continue }
            // 셀 각주는 행이 실리는 페이지에서 수집/예약되므로 예측에서도 제외
            if case .table = ctrl {
                continue
            }
            for (childIndex, (nested, _)) in childParagraphs(ctrl).enumerated()
                where nested.ctrlHeaderArray != nil
            {
                total += anticipatedFootnoteBodyHeight(
                    for: nested,
                    depth: depth + 1,
                    preview: &preview,
                    environment: environment,
                    childParagraphs: childParagraphs,
                    numbering: container?.paragraph(childIndex: childIndex)
                )
            }
        }
        return total
    }

    /// numbering: 이 각주 문단의 번호 열쇠 (#158) — 배치(`HwpFootnoteLayout.measure`)가
    /// `Input.numbering`으로 같은 라벨을 붙이므로 예약도 같은 열쇠로 잰다.
    /// isNoteEnd: 각주의 마지막 문단 — 마지막 줄의 줄 간격을 세지 않는다 (#165, 배치의
    /// `NoteMeasurement.stackingHeight`와 같은 산식). placedLineCount: 이어지는 조각의
    /// 앞 쪽에 실린 줄 수.
    /// sourceLayout: 이월 입력이 나른 원본 조판 — 있으면 줄 캐시를 문단에서 다시 만들지 않고
    /// 남은 줄의 높이도 누적표로 읽는다. lineLimit: 남은 줄 중 앞 몇 줄만 셀지 (다음 쪽에 실릴
    /// 조각, #165 리뷰) — nil이면 끝까지.
    mutating func measuredFootnoteHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment,
        numbering: HwpNumberingScope? = nil,
        isNoteEnd: Bool = false,
        placedLineCount: Int = 0,
        noteCarriesObjects: Bool = false,
        sourceLayout: HwpFootnoteLayout.SourceLayout? = nil,
        lineLimit: Int? = nil
    ) -> CGFloat {
        // 개체 없는 각주 (대다수) 는 라인 캐시만으로 끝낸다 — CT 조판을 건너뛰는
        // 이 빠른 길이 대형 문서 로드 시간을 좌우한다 (헌법주석 1,030쪽).
        // **개체를 담은 각주는 그 문단이 개체를 안 담아도** 이 길로 가지 않는다 (#165
        // 리뷰): 그런 각주는 전 문단이 CT 높이로 배치되므로 캐시 합을 돌려주면 예약이
        // 배치와 갈린다. 판정은 배치와 같은 **수집 대상 전체** 술어다 — 하한 술어
        // (`hasFloatingObject`)는 글 앞으로 그림을 빼 같은 각주를 다르게 본다.
        guard noteCarriesObjects || HwpParagraphObjectCollector.hasCollectibleObject(
            in: paragraph, collectsTextboxes: true, collectsTables: true
        ) else {
            return measuredFootnoteTextHeight(
                of: paragraph, number: number, environment: environment, numbering: numbering,
                isNoteEnd: isNoteEnd, placedLineCount: placedLineCount, sourceLayout: sourceLayout,
                lineLimit: lineLimit
            )
        }
        return measuredNoteBlockHeight(
            of: paragraph, number: number, environment: environment, numbering: numbering,
            isNoteEnd: isNoteEnd, placedLineCount: placedLineCount,
            noteCarriesObjects: noteCarriesObjects
        )
    }

    /// 개체를 담는 각주의 예약 높이 — 배치와 **같은 함수**
    /// (`HwpFootnoteLayout.measureNote`) 로 재서 줄 앵커 판정까지 일치시킨다.
    /// 예약이 줄 없는 프레임으로 따로 재면 앵커 있는 개체까지 하한을 받아
    /// 배치보다 커진다 (R40 #1).
    private mutating func measuredNoteBlockHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment,
        numbering: HwpNumberingScope?,
        isNoteEnd: Bool,
        placedLineCount: Int,
        noteCarriesObjects: Bool
    ) -> CGFloat {
        let width = environment.contentWidth
        let key = FootnoteHeightKey(
            paragraph: paragraph,
            widthCenti: Int(width * 100),
            number: number,
            sizeResolver: environment.sizeResolver?.forFootnoteArea(width: width),
            footnoteShape: environment.footnoteShape,
            numberingPath: numbering?.path,
            noteEnd: isNoteEnd,
            placedLineCount: placedLineCount,
            noteCarriesObjects: noteCarriesObjects
        )
        if let cached = footnoteBlockHeightCache[key] {
            return cached
        }
        let height = footnoteLayout.measureNote(
            paragraph,
            number: number,
            width: width,
            index: index,
            footnoteShape: environment.footnoteShape,
            sizeResolver: environment.sizeResolver,
            numbering: numbering,
            placedLineCount: placedLineCount,
            noteCarriesObjects: noteCarriesObjects
        ).stackingHeight(isNoteEnd: isNoteEnd)
        footnoteBlockHeightCache[key] = height
        return height
    }

    /// 각주 문단의 **텍스트** 높이 — 배치 (HwpFootnoteLayout.measure)와 같은
    /// 기준: 라인 캐시 우선. 쪽에 걸친 문단(세로 위치 리셋)도 쪽 몫의 합으로 잰다 (#165).
    private mutating func measuredFootnoteTextHeight(
        of paragraph: CoreHwp.HwpParagraph,
        number: Int,
        environment: Environment,
        numbering: HwpNumberingScope?,
        isNoteEnd: Bool,
        placedLineCount: Int,
        sourceLayout: HwpFootnoteLayout.SourceLayout?,
        lineLimit: Int? = nil
    ) -> CGFloat {
        if let lines = sourceLayout?.cacheLines ?? HwpFootnoteCacheLines.lines(of: paragraph) {
            let start = min(placedLineCount, lines.count)
            let range = start ..< (lineLimit.map { min(lines.count, start + max(0, $0)) } ?? lines.count)
            // 이월 입력은 남은 높이를 누적표로 읽는다 — 배치(`continuationMeasurement`)와 같은 값.
            // 앞 조각만 셀 때는 그 범위의 합이다 (`headHeight`와 같은 산식).
            let height = lineLimit == nil
                ? sourceLayout?.remainingHeight(from: start)
                ?? HwpFootnoteCacheLines.height(of: lines, in: range)
                : HwpFootnoteCacheLines.height(of: lines, in: range)
            return max(1, height
                - (isNoteEnd ? HwpFootnoteCacheLines.trailingSpacing(of: lines, in: range) : 0))
        }
        let width = environment.contentWidth
        let sizeResolver = environment.sizeResolver?.forFootnoteArea(width: width)
        let key = FootnoteHeightKey(
            paragraph: paragraph,
            widthCenti: Int(width * 100),
            number: number,
            sizeResolver: sizeResolver,
            footnoteShape: environment.footnoteShape,
            numberingPath: numbering?.path,
            noteEnd: false,
            placedLineCount: 0,
            noteCarriesObjects: false
        )
        if let cached = footnoteHeightCache[key] {
            return cached
        }

        let measured = HwpParagraphMeasurer(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: sizeResolver,
            attributeCache: attributeCache
        )
        .measure(
            paragraph,
            width: width,
            options: .init(
                controlReplacements: HwpTextRunBuilder.autoNumberReplacements(
                    in: paragraph,
                    number: number,
                    footnoteShape: environment.footnoteShape
                ),
                number: numbering?.number
            )
        )
        let height = max(1, measured.frame.totalHeight)
        footnoteHeightCache[key] = height
        return height
    }
}
