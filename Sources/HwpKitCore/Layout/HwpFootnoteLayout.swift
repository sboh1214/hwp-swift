import CoreGraphics
import CoreHwp
import Foundation

/// 페이지 하단 각주 영역 레이아웃.
///
/// 구분선 지오메트리 (길이/여백/색)는 구역 정의의 각주 모양 (HWPTAG_FOOTNOTE_SHAPE)에서
/// 가져오고, 길이가 자동(-1)이면 단 폭의 1/3을 쓴다.
public struct HwpFootnoteLayout {
    /// 측정(`HwpFootnoteNoteMeasurement.swift`)이 같은 해석기를 써야 하므로 모듈 안에서
    /// 보인다 — 공개 표면은 아니다.
    let fontResolver: HwpFontResolver
    /// 각주 문단이 본문과 같은 글자 모양 속성 캐시를 쓰게 한다 (소유는 `HwpPaginator`).
    let attributeCache: HwpTextAttributeCache?

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.init(fontResolver: fontResolver, attributeCache: nil)
    }

    /// 캐시를 주입하는 모듈 내부용 init (`HwpTextAttributeCache` 참조).
    init(fontResolver: HwpFontResolver, attributeCache: HwpTextAttributeCache?) {
        self.fontResolver = fontResolver
        self.attributeCache = attributeCache
    }

    public struct Input {
        public let paragraph: CoreHwp.HwpParagraph
        public let number: Int
        /// 이 각주를 **수집한 시점**의 크기 해석기 (R44 #1).
        ///
        /// `HwpPaginator.objectSizeResolver`는 현재 단·문단 폭을 읽는 계산
        /// 프로퍼티라 시점마다 값이 다르다. 예약은 수집 시점에 계산되는데 배치가
        /// 페이지 확정 시점의 값을 다시 읽으면, 그 사이 단 밴드가 바뀌거나 비등폭
        /// 단으로 넘어갔을 때 `.column`·`.paragraph` 기준 개체가 다른 크기로
        /// 재조판된다 (본문 겹침·없던 페이지 절단). 예약이 쓴 값을 그대로 실어
        /// 배치까지 들고 간다 — 예약 ≡ 배치의 **시간 축**이다.
        public let sizeResolver: HwpObjectSizeResolver?
        /// 이 문단의 문단 번호·개요 번호 열쇠 (#158) — 수집기가 컨트롤 서수와 리스트
        /// 서수로 풀어 싣는다. 예약(`HwpFootnoteCoordinator`)과 배치(`measureNote`)가
        /// 같은 열쇠로 같은 라벨을 붙여야 높이가 갈리지 않는다. 공개 init은 nil이다.
        let numbering: HwpNumberingScope?
        /// 앞 쪽들에 이미 실린 이 문단의 캐시 줄 수 (#165) — 0이면 문단 처음부터다.
        /// 이어지는 조각은 그 뒤 줄만 재고 그리며 번호 라벨을 반복하지 않는다
        /// (`HwpFootnoteContinuation.swift`). 공개 init은 0이다.
        let placedLineCount: Int
        /// 앞 쪽들이 이미 **그린** 조판 문자열 길이 (#165 리뷰) — 이어지는 조각의 시작
        /// 문자 위치다. 캐시 줄 인덱스를 CT 줄 수에 비례 환산한 경계는 구역이 바뀌어 폭이
        /// 달라지면 (줄 나눔이 달라져) 앞 쪽이 실제로 그린 마지막 글자와 다른 자리를
        /// 가리켜 글자가 사라지거나 겹친다 (실측: 451 → 200pt에서 7자 유실). 폭이 그대로면
        /// 비례 환산 결과가 곧 이 위치라 동작이 같다. 공개 init은 0이다.
        let placedLength: Int
        /// 각주 하나의 **식별자** (#165 리뷰) — 문서 순서 일련번호라 표시 번호와 달리
        /// 쪽마다 새로 시작해도 (표 134 모드 2) 재사용되지 않는다. 여러 문단짜리 각주는
        /// 같은 값을 공유하고 이월된 조각도 그대로 물려받는다. 표시 번호로 그룹을 나누면
        /// 이월된 각주와 새 각주가 한 각주로 합쳐져 사이 여백이 사라지고 앞 조각의 마지막
        /// 줄 간격이 높이에 남는다. 공개 init은 표시 번호를 그대로 쓴다.
        let noteId: Int
        /// 이 각주를 **처음 잰** 각주 모양 (#165 리뷰). 번호 라벨은 구역 각주 모양의
        /// 장식 문자·번호 모양을 따르므로, 구역이 바뀐 쪽에서 다시 만들면 라벨 길이가
        /// 달라져 조판 문자열이 통째로 밀린다 — `placedLength`가 가리키는 자리가 어긋나
        /// 이어지는 글자가 잘리거나 겹친다. 예약도 이 모양으로 쟀으므로 배치와 같은 값을
        /// 써야 예약 ≡ 배치가 성립한다 (`sizeResolver`와 같은 이유·같은 규약, R44 #1).
        ///
        /// `nil`은 **아직 재지 않은** 상태다. 잰 결과가 기본 모양(구역 모양 없음)이면
        /// `MeasuredShape(footnoteShape: nil)`로 **확정된** 상태다 — 둘을 같은 nil로 두면
        /// 기본 모양으로 잰 이월 입력이 다음 쪽의 모양을 새로 채택해 문자열이 밀린다
        /// (실측: `1` → `(1)`에서 앞 조각의 마지막 두 글자가 겹쳐 그려짐). `measure`가
        /// 처음 잰 값을 채워 이월 입력에 실어 보낸다.
        let measuredShape: MeasuredShape?
        /// 앞 쪽이 잰 문단 **전체**의 조판 (#165 리뷰) — 이어지는 조각은 원본에서 잘라 내므로
        /// 같은 폭이면 다시 조판하지 않는다 (`SourceLayout`). 이월 입력에만 실린다.
        let sourceLayout: SourceLayout?

        /// 처음 잰 각주 모양의 확정 표식 — 값이 nil이어도 "기본 모양으로 잼"이다.
        struct MeasuredShape {
            let footnoteShape: CoreHwp.HwpFootnoteShape?
        }

        /// - Parameter noteId: 각주 하나를 가르는 식별자. 생략하면 표시 번호를 쓴다 —
        ///   쪽마다 번호를 새로 시작하는 문서(표 134 모드 2)에서 이월 조각과 새 각주가
        ///   같은 번호를 갖는 경우처럼 **표시 번호가 겹칠 때** 직접 지정한다. 겹친 채 두면
        ///   둘이 한 각주로 묶여 사이 여백이 사라지고, 남은 자리에 들어가는 이월 조각까지
        ///   함께 다음 쪽으로 밀린다.
        public init(
            paragraph: CoreHwp.HwpParagraph,
            number: Int,
            sizeResolver: HwpObjectSizeResolver? = nil,
            noteId: Int? = nil
        ) {
            self.init(
                paragraph: paragraph, number: number, sizeResolver: sizeResolver,
                numbering: nil, noteId: noteId ?? number
            )
        }

        init(
            paragraph: CoreHwp.HwpParagraph,
            number: Int,
            sizeResolver: HwpObjectSizeResolver?,
            numbering: HwpNumberingScope?,
            placedLineCount: Int = 0,
            placedLength: Int = 0,
            noteId: Int,
            measuredShape: MeasuredShape? = nil,
            sourceLayout: SourceLayout? = nil
        ) {
            self.paragraph = paragraph
            self.number = number
            self.sizeResolver = sizeResolver
            self.numbering = numbering
            self.placedLineCount = placedLineCount
            self.placedLength = placedLength
            self.noteId = noteId
            self.measuredShape = measuredShape
            self.sourceLayout = sourceLayout
        }

        /// 처음 잰 각주 모양을 **확정**한 사본 — 기본 모양(nil)으로 잰 것도 확정이다.
        func withMeasuredShape(_ shape: CoreHwp.HwpFootnoteShape?) -> Input {
            Input(
                paragraph: paragraph, number: number, sizeResolver: sizeResolver,
                numbering: numbering, placedLineCount: placedLineCount,
                placedLength: placedLength, noteId: noteId,
                measuredShape: MeasuredShape(footnoteShape: shape),
                sourceLayout: sourceLayout
            )
        }
    }

    /// 배치 결과: 이 페이지에 들어간 블록과 다음 페이지로 이월할 입력.
    public struct Placement {
        public let blocks: [HwpFootnoteBlock]
        public let overflow: [Input]
    }

    /// 페이지네이터용 배치 결과 — 이월은 대기 목록(`PendingNotes`)이라 복사가 없다; 공개
    /// 경계(`Placement`)에서만 배열로 만든다.
    struct PendingPlacement {
        let blocks: [HwpFootnoteBlock]
        let overflow: PendingNotes
    }

    /// 페이지 하단에 배치할 각주 블록들을 계산한다.
    ///
    /// - Parameters:
    ///   - footnotes: 이 페이지의 각주 문단 + 문서 순서 번호
    ///   - geometry: 페이지 지오메트리
    ///   - index: id 매핑 인덱스
    ///   - footnoteShape: 구역의 각주 모양 (nil이면 기본값)
    /// - Returns: 페이지 좌표계의 각주 블록 (아래에서 위로 쌓아 올린 결과)
    public func layout(
        footnotes: [Input],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> [HwpFootnoteBlock] {
        place(
            footnotes: footnotes,
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        ).blocks
    }

    /// 예약 기하 — paginator가 본문 배치 전에 각주 영역 높이를 예측할 때
    /// 실제 배치 (place의 스택 산식)와 동형이 되도록 노출한다:
    /// 예약 = Σ 각주 높이 (각주 마지막 줄의 줄 간격 제외)
    ///       + spacingBetweenNotes × (노트 경계 수) + separatorOverhead (페이지 첫 각주만).
    public struct ReservationMetrics {
        /// 구분선 위 여백 + 아래 여백 (place의 stackHeight와 동일). 선 두께는 세지 않는다 —
        /// 한글은 선을 위 여백 끝에 가운데 맞춰 긋고 아래 여백을 선 가운데부터 잰다 (#165 실측).
        public let separatorOverhead: CGFloat
        /// 서로 다른 번호의 노트 사이 간격 (같은 번호의 이어지는 문단은 0)
        public let spacingBetweenNotes: CGFloat
    }

    public func reservationMetrics(
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        contentWidth: CGFloat
    ) -> ReservationMetrics {
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: contentWidth
        )
        return ReservationMetrics(
            separatorOverhead: divider.marginTop + divider.marginBottom,
            spacingBetweenNotes: divider.betweenNotes
        )
    }

    /// 각주 영역에 들어가는 만큼 배치하고 나머지는 이월로 돌려준다.
    ///
    /// limitsAreaToHalfContent: 흐름 조판에선 콘텐츠 절반 상한 (한글 기본 동작) — 넘는
    /// 각주는 통째로 이월하되 진행 보장을 위해 첫 각주는 영역보다 커도 항상 배치한다.
    /// 절대 캐시 모드에선 false — 본문이 남긴 자리(`bodyBottom` 아래)에 한글의 이어짐
    /// 규칙으로 싣는다: 안 들어가는 각주는 줄 캐시의 분할 지점에서 나눠 다음 쪽 첫 각주로
    /// 잇고, 분할 지점이 없으면 통째로 옮긴다 (#165, `HwpFootnoteContinuation.swift`).
    /// bodyBottom: 이 쪽 본문의 하한 (마지막 줄 **상자** 아래, 줄 간격 제외) — nil이면
    /// 본문 없는 쪽 (이월 드레인) 이라 콘텐츠 전체가 자리다.
    public func place(
        footnotes: [Input],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        limitsAreaToHalfContent: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil,
        bodyBottom: CGFloat? = nil
    ) -> Placement {
        let placement = placePending(
            footnotes: PendingNotes(footnotes[...]),
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape,
            limitsAreaToHalfContent: limitsAreaToHalfContent,
            sizeResolver: sizeResolver,
            bodyBottom: bodyBottom
        )
        return Placement(blocks: placement.blocks, overflow: placement.overflow.array)
    }

    /// `place`의 대기 목록 판 — 페이지네이터가 대기 각주 저장소를 복사 없이 넘기고 받는다.
    func placePending(
        footnotes: PendingNotes,
        onPage geometry: HwpPageGeometry,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        limitsAreaToHalfContent: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil,
        bodyBottom: CGFloat? = nil
    ) -> PendingPlacement {
        guard !footnotes.isEmpty else { return PendingPlacement(blocks: [], overflow: PendingNotes()) }

        let contentFrame = geometry.contentFrame
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: contentFrame.width
        )

        // 블록 높이는 스택이 보는 순서대로 **필요할 때** 잰다 (#165 리뷰, `MeasuredNotes`).
        let notes = measuredNotes(
            footnotes,
            index: index,
            width: contentFrame.width,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        )

        // 절대 캐시 모드 (상한 없음): 본문 아래 자리에 맞춰 싣고 넘치는 몫은 한글의 분할
        // 지점에서 나눠 다음 쪽으로 잇는다 (#165).
        if !limitsAreaToHalfContent {
            return placeBelowBody(
                notes: notes, bodyBottom: bodyBottom, onPage: geometry, divider: divider
            )
        }

        // 페이지 하단에서 위로 필요한 만큼 확보하되 콘텐츠 절반을 넘지 않는다.
        // 같은 각주 컨트롤의 이어지는 문단 사이에는 간격이 없고 (stackBlocks와 동일)
        // 각주 마지막 줄의 줄 간격은 세지 않는다 (#165 실측). 절반을 넘은 뒤의 각주는
        // 재지 않는다 — 상한이 정해지면 그 값은 더 필요 없다.
        let halfContent = contentFrame.height / 2
        let stackHeight = Self.stackedHeight(
            of: notes, betweenNotes: divider.betweenNotes, upTo: halfContent
        ) + divider.marginTop + divider.marginBottom
        let areaHeight = min(halfContent, stackHeight)
        // 각주 영역 상단은 본문 상단 아래로 내려오지 못한다 (#95) — 절반 상한 모드는
        // areaHeight ≤ 콘텐츠/2라 이 클램프가 무동작이다.
        let areaTop = max(contentFrame.minY, contentFrame.maxY - areaHeight)
        let separatorLine = Self.separatorLine(
            areaTop: areaTop, divider: divider, contentFrame: contentFrame
        )
        let stacked = stackBlocks(
            notes: notes,
            from: areaTop + divider.marginTop + divider.marginBottom,
            in: contentFrame,
            separatorLine: separatorLine,
            divider: divider
        )
        return PendingPlacement(blocks: stacked.blocks, overflow: stacked.overflow)
    }

    /// 각주 항목들의 스택 높이 — 항목 높이 (각주 마지막 항목은 마지막 줄 줄 간격 제외)
    /// + 서로 다른 번호 사이의 간격. 예약(`HwpFootnoteCoordinator`)이 같은 산식을 쓴다.
    /// `limit`을 넘으면 거기서 멈춘다 (넘었다는 사실만 필요한 호출자가 뒤 각주를 재지 않게).
    static func stackedHeight(
        of notes: MeasuredNotes, betweenNotes: CGFloat, upTo limit: CGFloat = .infinity
    ) -> CGFloat {
        var total: CGFloat = 0
        for index in 0 ..< notes.count {
            // `where`로 거르면 몸통만 건너뛰고 남은 각주를 끝까지 훑는다 (#165 리뷰) — 넘은 순간 끝낸다.
            guard total <= limit else { break }
            if index > 0, notes.noteId(at: index - 1) != notes.noteId(at: index) {
                total += betweenNotes
            }
            let isNoteEnd = index == notes.count - 1
                || notes.noteId(at: index + 1) != notes.noteId(at: index)
            total += notes[index].measurement.stackingHeight(isNoteEnd: isNoteEnd)
        }
        return total
    }

    /// 구분선 rect — 위 여백 끝에 **가운데** 맞춘다 (한글 실측: 첫 각주 줄 위 = 선 가운데
    /// + 아래 여백). 두께는 그리기용 하한 0.5pt.
    static func separatorLine(
        areaTop: CGFloat, divider: DividerMetrics, contentFrame: CGRect
    ) -> CGRect {
        let thickness = max(0.5, divider.thickness)
        return CGRect(
            x: contentFrame.minX,
            y: areaTop + divider.marginTop - thickness / 2,
            width: divider.length,
            height: thickness
        )
    }

    /// 구분선 획이 각주 영역 위(`areaTop`)로 나가는 몫 — 위 여백이 획 반 두께보다 좁을 때만
    /// 0보다 크다 (`separatorLine`과 같은 두께 하한).
    static func separatorOverhang(_ divider: DividerMetrics) -> CGFloat {
        max(0, max(0.5, divider.thickness) / 2 - divider.marginTop)
    }

    /// 흐름 배치 결과: 배치된 블록, 이월 입력, 다음 흐름 y
    public struct FlowPlacement {
        public let blocks: [HwpFootnoteBlock]
        public let overflow: [Input]
        public let bottom: CGFloat
    }

    /// 페이지네이터용 흐름 배치 결과 — 이월은 대기 목록 (`PendingPlacement`와 같은 이유).
    struct PendingFlowPlacement {
        let blocks: [HwpFootnoteBlock]
        let overflow: PendingNotes
        let bottom: CGFloat
    }

    /// 미주처럼 흐름 위치에서 아래로 쌓는 배치 (문서/구역 끝).
    ///
    /// - Parameters:
    ///   - footnotes: 배치할 미주 문단 + 번호
    ///   - startY: 시작 y (페이지 좌표)
    ///   - columnFrame: 배치할 단 프레임 (maxY가 하한)
    ///   - drawSeparator: 첫 블록 위에 구분선을 둘지 (이월 연속 배치면 false)
    /// - Returns: columnFrame 하한을 넘는 입력은 overflow로 돌려준다.
    ///   진행 보장을 위해 첫 블록은 항상 배치한다.
    public func placeFlow(
        footnotes: [Input],
        from startY: CGFloat,
        in columnFrame: CGRect,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        drawSeparator: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> FlowPlacement {
        let placement = placePendingFlow(
            footnotes: PendingNotes(footnotes[...]),
            from: startY,
            in: columnFrame,
            index: index,
            footnoteShape: footnoteShape,
            drawSeparator: drawSeparator,
            sizeResolver: sizeResolver
        )
        return FlowPlacement(
            blocks: placement.blocks, overflow: placement.overflow.array, bottom: placement.bottom
        )
    }

    /// `placeFlow`의 대기 목록 판 — 페이지네이터가 대기 미주 저장소를 복사 없이 넘기고 받는다.
    func placePendingFlow(
        footnotes: PendingNotes,
        from startY: CGFloat,
        in columnFrame: CGRect,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        drawSeparator: Bool = true,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> PendingFlowPlacement {
        guard !footnotes.isEmpty else {
            return PendingFlowPlacement(blocks: [], overflow: PendingNotes(), bottom: startY)
        }
        let divider = dividerMetrics(
            from: footnoteShape?.dividerInfo,
            contentWidth: columnFrame.width
        )
        let notes = measuredNotes(
            footnotes,
            index: index,
            width: columnFrame.width,
            footnoteShape: footnoteShape,
            sizeResolver: sizeResolver
        )

        var cursorY = startY
        var separatorLine = CGRect(x: columnFrame.minX, y: startY, width: 0, height: 0)
        if drawSeparator {
            separatorLine = Self.separatorLine(
                areaTop: cursorY, divider: divider, contentFrame: columnFrame
            )
            cursorY += divider.marginTop + divider.marginBottom
        }

        return stackBlocks(
            notes: notes,
            from: cursorY,
            in: columnFrame,
            separatorLine: separatorLine,
            divider: divider
        )
    }

    /// 각주들을 frame 폭으로 위에서 아래로 쌓는다 — 측정은 쌓는 순서대로 필요할 때
    /// (`MeasuredNotes`), 넘친 뒤의 각주는 재지 않는다.
    /// frame.maxY를 넘는 입력은 overflow로 돌려주되, 진행 보장을 위해
    /// 첫 블록은 항상 배치한다. 블록 산식은 절대 캐시 모드 (`placeBelowBody`)와
    /// 같은 `footnoteBlock(for:)`이다.
    private func stackBlocks(
        notes: MeasuredNotes,
        from startY: CGFloat,
        in frame: CGRect,
        separatorLine: CGRect,
        divider: DividerMetrics
    ) -> PendingFlowPlacement {
        var blocks: [HwpFootnoteBlock] = []
        var overflow = PendingNotes()
        var cursorY = startY
        var previousNoteId: Int?
        for noteIndex in 0 ..< notes.count {
            let note = notes[noteIndex]
            // 같은 각주 컨트롤의 이어지는 문단은 간격 없이 붙인다
            // (헌법주석 실측: 한 각주의 문단 캐시 loc이 연속 — 내부 간격 0).
            if let previousNoteId, previousNoteId == note.input.noteId {
                cursorY -= divider.betweenNotes
            }
            let isNoteEnd = noteIndex == notes.count - 1
                || notes.noteId(at: noteIndex + 1) != note.input.noteId
            let entry = StackEntry(measured: note, lineRange: nil, isNoteEnd: isNoteEnd)
            let blockHeight = note.measurement.stackingHeight(isNoteEnd: isNoteEnd)
            if !blocks.isEmpty, cursorY + blockHeight > frame.maxY + 0.5 {
                overflow = notes.inputs(from: noteIndex)
                break
            }
            previousNoteId = note.input.noteId
            blocks.append(Self.footnoteBlock(
                for: entry, at: cursorY, in: frame, separatorLine: separatorLine, divider: divider
            ))
            cursorY += blockHeight + divider.betweenNotes
        }
        return PendingFlowPlacement(blocks: blocks, overflow: overflow, bottom: cursorY)
    }

    /// 높이 계산이 끝난 각주 문단 (+ 그 문단에 붙은 개체, 문단-로컬 rect)
    struct MeasuredFootnote {
        let input: Input
        let measurement: NoteMeasurement

        var attributed: NSAttributedString {
            measurement.attributed
        }

        var frame: HwpParagraphFrame {
            measurement.frame
        }

        var objects: HwpParagraphObjectCollector.Objects {
            measurement.objects
        }

        var textRectHeight: CGFloat {
            measurement.textRectHeight
        }

        var blockHeight: CGFloat {
            measurement.blockHeight
        }
    }
}

// MARK: - 구분선 기하

extension HwpFootnoteLayout {
    /// 각주 모양에서 해석한 구분선 지오메트리 (point 단위)
    struct DividerMetrics {
        let marginTop: CGFloat
        let marginBottom: CGFloat
        let betweenNotes: CGFloat
        let length: CGFloat
        let color: HwpRGBColor
        let thickness: CGFloat
    }

    private func dividerMetrics(
        from divider: CoreHwp.HwpFootnoteDividerInfo?,
        contentWidth: CGFloat
    ) -> DividerMetrics {
        let length: CGFloat = if let length = divider?.length, length > 0 {
            min(contentWidth, HwpUnits.points(fromHwpUnit: length))
        } else {
            contentWidth / 3
        }
        return DividerMetrics(
            marginTop: max(0, points(
                fromHwpUnit16: divider?.marginTop,
                fallback: HwpRenderTuning.Footnote.dividerDefaultMarginTop
            )),
            marginBottom: max(0, points(
                fromHwpUnit16: divider?.marginBottom,
                fallback: HwpRenderTuning.Footnote.dividerDefaultMarginBottom
            )),
            betweenNotes: max(0, points(
                fromHwpUnit16: divider?.spacingBetweenNotes,
                fallback: HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes
            )),
            length: length,
            color: divider.map { HwpRGBColor($0.color) }
                ?? HwpRGBColor(red: 0, green: 0, blue: 0),
            thickness: divider.map {
                CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: $0.thickness))
            } ?? 1
        )
    }
}

private extension HwpFootnoteLayout {
    /// 개체 수집에 쓰는 문단-로컬 rect. `stackBlocks`의 문단 rect와 원점이 같아야
    /// 수집 좌표가 곧 블록-로컬 좌표다. 높이는 **텍스트 높이**를 쓴다 — 블록
    /// 높이는 이 수집 결과에서 나오므로 순환을 피하고, 예약 경로
    /// (`HwpFootnoteCoordinator`)가 같은 rect로 재수집해 값이 갈리지 않게 한다.
    internal static func paragraphRect(width: CGFloat, textHeight: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: textHeight)
    }

    func points(fromHwpUnit16 value: Int16?, fallback: CGFloat) -> CGFloat {
        guard let value else { return fallback }
        return HwpUnits.points(fromHwpUnit16: value)
    }
}
