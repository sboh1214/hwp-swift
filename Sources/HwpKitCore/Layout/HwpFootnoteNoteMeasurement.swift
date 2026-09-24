import CoreGraphics
import CoreHwp
import Foundation

// 각주 문단 하나의 측정 — 예약(`HwpFootnoteCoordinator`)과 배치(`HwpFootnoteLayout`)가
// **이 한 함수**를 공유한다 (산식을 복제하면 두 경로가 갈려 각주가 본문을 덮거나 한글에
// 없는 쪽 절단이 생긴다). `HwpFootnoteLayout.swift`가 SwiftLint file_length 상한(700줄)에
// 닿아 갈라 뒀다.

// MARK: - 예약·배치 공유 측정

extension HwpFootnoteLayout {
    /// 각주 문단 하나의 측정 결과 — 텍스트·개체·높이.
    struct NoteMeasurement {
        /// 조각의 조판 문자열 — 이어지는 조각은 **처음 읽을 때** 원본에서 잘라 낸다 (`text`).
        var attributed: NSAttributedString {
            text.attributed
        }

        /// 조각의 문단 프레임 — 높이는 즉시 값(`totalHeight`), 줄 프레임은 `text`처럼 지연.
        var frame: HwpParagraphFrame {
            HwpParagraphFrame(totalHeight: totalHeight, lines: text.lines)
        }

        /// 조각 텍스트 높이 (문단 rect 높이의 원값) — 캐시 합 또는 CT 높이.
        let totalHeight: CGFloat
        /// 조각의 조판 문자열·줄 프레임 공급자 (#165 리뷰). 이어지는 조각은 실제로 실릴 때
        /// (통째로 실리는 한 번) 만 원본에서 잘라 낸다 — 쪽마다 남은 문단 전체를 미리 잘라
        /// 두면 (`attributedSubstring`) 이월이 길게 이어지는 문단에서 쪽 수 × 남은 글자 수의
        /// 일이 된다 (실측: 8,000줄·399쪽 합성 각주가 원본 조판을 나른 뒤에도 22.4s, 그중
        /// 84%가 이 잘라 내기 → 지연 뒤 2.5s). 스택 계획은 높이(`totalHeight`)만 읽으므로 이
        /// 지연이 판정을 바꾸지 않는다.
        let text: LazyText
        let objects: HwpParagraphObjectCollector.Objects
        /// 문단 **전체**의 조판 문자열·줄 프레임 (#165 리뷰) — 조각 경계는 언제나 여기에
        /// **절대** 캐시 줄 인덱스를 적용해 잰다.
        ///
        /// `attributed`/`frame`은 이미 잘린 조각이라, 이어지는 조각을 쪽 끝에서 다시 나눌
        /// 때 그것을 **남은 줄 기준**으로 재환산하면 다음 쪽이 문단 전체 기준으로 다시
        /// 계산한 경계와 반올림에서 갈린다 — 캐시 4줄·CT 5줄을 세 쪽에 나누면 가운데 줄이
        /// 통째로 사라지고 (반대 비율이면 중복된다). 두 경로가 같은 원본·같은 인덱스를
        /// 쓰면 그 어긋남이 원천적으로 없다.
        let sourceAttributed: NSAttributedString
        let sourceLines: [HwpLineFrame]
        /// 문단 줄 캐시 (#165) — 분할 지점·조각 높이의 근거. 캐시가 없으면 nil.
        let cacheLines: [HwpFootnoteCacheLine]?
        /// 앞 쪽에 이미 실린 줄 수 — `attributed`·`frame`은 그 뒤 조각이다.
        let placedLineCount: Int
        /// 앞 쪽이 소비한 조판 문자열 길이 (#165 리뷰 — `Input.placedLength`)
        let placedLength: Int
        /// 이 **각주**(문단 전체)가 그릴 개체를 담는지 — 쪽 끝 분할 금지·CT 높이 보존
        /// 술어 (#165 리뷰). 분할 금지가 각주 단위인데 높이 보존만 문단 단위면, 개체가
        /// 없는 앞 문단이 캐시 합으로 줄어 그 문단의 마지막 글줄 위로 뒤 문단의 그림이
        /// 올라온다 — 두 판정의 범위를 맞춘다.
        let carriesObjects: Bool
        /// 마지막 줄 상자 아래 몫 — 텍스트 높이가 캐시에서 왔으면 그 마지막 줄의 줄 간격, CT로
        /// 쟀으면 그 프레임의 마지막 줄 상자 아래 몫(#222)이다. 각주 끝·쪽 끝에서 세지 않는다
        /// (각주 사이 여백이 대체하고, 쪽 끝은 줄 상자 아래가 본문 하단에 닿는다).
        let trailingLineSpacing: CGFloat
        /// `sourceAttributed`/`sourceLines`를 조판한 폭 — 이월 입력이 원본을 나를 때 폭이
        /// 같은지 가리는 열쇠 (#165 리뷰, `SourceLayout`).
        let sourceWidth: CGFloat
        /// 이어지는 조각이 잰 원본 조판 (나른 것 또는 이 쪽에서 새로 만든 것) — 통째 측정은
        /// nil이고 처음 나뉠 때 `carriedSourceLayout`이 한 번 만든다.
        let sourceLayout: SourceLayout?

        /// 이월 입력에 실어 보낼 원본 조판 — 줄 캐시가 없는 문단은 나뉘지 않으므로 nil.
        /// 이어지는 조각은 잰 원본을 **그대로** 넘겨 쪽마다 다시 만들지 않는다 (#165 리뷰).
        func carriedSourceLayout() -> SourceLayout? {
            if let sourceLayout {
                return sourceLayout
            }
            return cacheLines.map {
                SourceLayout(
                    width: sourceWidth, attributed: sourceAttributed, lines: sourceLines,
                    cacheLines: $0
                )
            }
        }

        /// 문단 rect 높이 — **문단 자신의** 텍스트 높이. 블록 높이와 달리 개체
        /// 성장분을 포함하지 않는다 (R39 #2).
        var textRectHeight: CGFloat {
            max(1, totalHeight)
        }

        /// 블록 높이 — 텍스트 높이와 **떠 있는** 개체 하단의 최대값 (#94).
        ///
        /// 글자처럼 취급 개체는 라인 캐시가 이미 담는 몫이라 (헌법주석 실측:
        /// 883쪽 각주 29의 408×62.52pt 표가 캐시 71.32pt 안에, 459쪽 각주 38의
        /// 9.6×10.8pt 그림이 3줄 36.96pt 안에 들어간다) 하한을 얹지 않는다 —
        /// 얹으면 캐시를 신뢰하는 규약이 깨져 페이지 절단이 한글과 어긋난다.
        /// 떠 있는 개체는 캐시에 없으므로 (한글.app 합성 실측 2026-07-30: 각주
        /// 문단에 떠 있는 도형을 붙이면 구분선이 위로 밀려 각주 영역이 개체를
        /// 담는다) `HwpParagraphObjectCollector.raisesContainerFloor` 술어로
        /// 담는다 — 떠 있는 개체와, 줄 앵커를 못 얻어 어떤 줄도 자리를 잡아
        /// 주지 않은 글자처럼 취급 개체 (R40 #1) 둘 다.
        var blockHeight: CGFloat {
            Swift.max(textRectHeight, objects.floatingBottom ?? 0)
        }

        /// 스택에서 차지하는 높이 — 각주의 마지막 항목이면 마지막 줄의 줄 간격을 뺀다
        /// (#165 실측). 문단 rect(`textRectHeight`)는 그대로 둔다 — CT가 그 안에 줄을
        /// 놓으므로 줄 간격 몫을 잘라 내면 대체 폰트의 마지막 줄이 프레임 밖으로 떨어진다.
        func stackingHeight(isNoteEnd: Bool) -> CGFloat {
            let text = isNoteEnd ? textRectHeight - trailingLineSpacing : textRectHeight
            return Swift.max(1, Swift.max(text, objects.floatingBottom ?? 0))
        }

        /// 쪽 끝에서 나뉜 앞 몫 (남은 줄 기준 `range`) 의 텍스트 높이 — 마지막 줄 전진량까지.
        func headTextHeight(lines range: Range<Int>) -> CGFloat {
            guard let cacheLines else { return textRectHeight }
            return Swift.max(1, HwpFootnoteCacheLines.height(of: cacheLines, in: absoluteLineRange(range)))
        }

        /// 앞 몫의 스택 높이 — 마지막 줄 상자까지 (그 줄의 줄 간격 제외).
        func headHeight(lines range: Range<Int>) -> CGFloat {
            guard let cacheLines else { return stackingHeight(isNoteEnd: true) }
            let text = HwpFootnoteCacheLines.height(of: cacheLines, in: absoluteLineRange(range))
                - HwpFootnoteCacheLines.trailingSpacing(of: cacheLines, in: absoluteLineRange(range))
            return Swift.max(1, Swift.max(text, objects.floatingBottom ?? 0))
        }

        /// 남은 줄 기준 범위를 문단 **전체** 기준 캐시 줄 범위로 옮긴다 (#165 리뷰) —
        /// 높이도 조각 문자열도 이 절대 인덱스 하나로만 잰다.
        func absoluteLineRange(_ range: Range<Int>) -> Range<Int> {
            let count = cacheLines?.count ?? 0
            let lower = Swift.min(placedLineCount + range.lowerBound, count)
            let upper = Swift.min(Swift.max(lower, placedLineCount + range.upperBound), count)
            return lower ..< upper
        }
    }

    /// 조판 문자열·줄 프레임의 지연 공급자 — 통째 측정은 즉시 값이고, 이어지는 조각은 처음
    /// 읽을 때 한 번 잘라 낸 뒤 그 값을 보관한다. 측정은 `place` 한 호출 안에서만 살고
    /// 넘어가지 않으므로 (이월은 `Input`) 동기 접근만 있다.
    final class LazyText {
        private let make: () -> (attributed: NSAttributedString, lines: [HwpLineFrame])
        private lazy var value = make()

        init(attributed: NSAttributedString, lines: [HwpLineFrame]) {
            make = { (attributed, lines) }
        }

        init(_ make: @escaping () -> (attributed: NSAttributedString, lines: [HwpLineFrame])) {
            self.make = make
        }

        var attributed: NSAttributedString {
            value.attributed
        }

        var lines: [HwpLineFrame] {
            value.lines
        }
    }

    /// 각주 문단 하나를 재고 그 문단에 붙은 개체를 문단-로컬 rect로 수집한다.
    ///
    /// 예약 (`HwpFootnoteCoordinator`) 과 배치 (`stackBlocks`) 가 **이 함수
    /// 하나만** 쓴다 — 산식을 복제하면 두 경로가 갈려 각주 스택이 본문을 덮거나
    /// 한글에 없는 페이지 절단이 생긴다 (#94, R39 #1). 특히 줄 앵커 유무가 개체
    /// 높이 하한을 가르므로 (`escapesLineBox`) 양쪽이 **같은 프레임**을 봐야
    /// 한다 — 예약이 줄 없는 프레임으로 따로 재던 것이 R40 #1의 원인이었다.
    ///
    /// placedLineCount: 앞 쪽들에 이미 실린 캐시 줄 수 (#165) — 0보다 크면 그 뒤 줄만
    /// 재고 조각 문자열을 만든다 (개체는 첫 조각 몫이라 수집하지 않는다).
    /// sourceLayout: 앞 쪽이 잰 문단 전체의 조판 (#165 리뷰) — 폭이 같으면 다시 조판하지
    /// 않고 그 원본에서 조각을 잘라 낸다. 쪽마다 문단 전체를 CT로 다시 조판하면 이월이
    /// 길게 이어지는 문단에서 쪽 수 × 줄 수의 일이 된다.
    func measureNote(
        _ paragraph: CoreHwp.HwpParagraph,
        number: Int,
        width: CGFloat,
        index: HwpIndex,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        sizeResolver: HwpObjectSizeResolver?,
        numbering: HwpNumberingScope? = nil,
        placedLineCount: Int = 0,
        placedLength: Int = 0,
        noteCarriesObjects: Bool = false,
        sourceLayout: SourceLayout? = nil
    ) -> NoteMeasurement {
        let noteResolver = sizeResolver?.forFootnoteArea(width: width)
        let tableHeights = inlineTableHeights(
            of: paragraph, width: width, index: index, resolver: noteResolver, numbering: numbering
        )
        /// 각주 첫머리의 자동 번호 (ext18) 마커를 번호 문자열로 치환한다 (번호는
        /// paginator가 부여한 문서 순서 번호 — 본문 참조와 동일 소스). 스택
        /// 높이는 한글 라인 캐시를 우선한다 (본문 절대 캐시와 동일 철학) — 표를 실은 캐시
        /// 줄이 그 표보다 낮으면(`HwpParagraphLayout.lineCacheIsStale`) CT 높이다.
        /// 문단 번호·개요 번호 라벨(#158)은 자동 번호 앞에 전치된다. 글자처럼 취급 표는
        /// 수집기(아래)가 그릴 높이로 줄을 예약한다 (#214).
        func layOut(preferCachedHeight: Bool = true) -> HwpParagraphMeasurer.Result {
            HwpParagraphMeasurer(
                index: index,
                fontResolver: fontResolver,
                sizeResolver: noteResolver,
                attributeCache: attributeCache
            )
            .measure(
                paragraph,
                width: width,
                options: .init(
                    controlReplacements: HwpTextRunBuilder.autoNumberReplacements(
                        in: paragraph,
                        number: number,
                        footnoteShape: footnoteShape
                    ),
                    preferCachedHeight: preferCachedHeight,
                    number: numbering?.number,
                    inlineTableHeights: tableHeights
                )
            )
        }
        // 줄 캐시는 문단의 것이라 폭과 무관하다 — 나른 것이 있으면 다시 만들지 않는다.
        let cacheLines = sourceLayout?.cacheLines ?? HwpFootnoteCacheLines.lines(of: paragraph)
        // 이어지는 조각 (#165): 앞 쪽에 실린 줄 뒤만 재고 그린다 — 원본은 같은 폭으로 나른
        // 조판이 있으면 그것이고, 없거나 폭이 달라졌으면 (구역 변경) 다시 조판한다.
        if let cacheLines, placedLineCount > 0 {
            let layout: SourceLayout
            if let sourceLayout, sourceLayout.width == width {
                layout = sourceLayout
            } else {
                let measured = layOut()
                layout = SourceLayout(
                    width: width, attributed: measured.attributed, lines: measured.frame.lines,
                    cacheLines: cacheLines
                )
            }
            return Self.continuationMeasurement(
                layout: layout, placedLineCount: placedLineCount, placedLength: placedLength,
                noteCarriesObjects: noteCarriesObjects
            )
        }
        // 표를 실은 캐시 줄이 그 표보다 낮으면 캐시가 낡았다 — 표 줄이 커지며 아래 줄이 모두
        // 내려가므로 캐시 높이 대신 CT 높이로 잰다 (#214 리뷰, `HwpParagraphLayout.lineCacheIsStale`).
        let measured = layOut(
            preferCachedHeight: !HwpParagraphLayout.lineCacheIsStale(
                paragraph, inlineTableHeights: tableHeights
            )
        )
        // 각주 문단에 붙은 개체 (그림/도형/글상자/표)는 각주 영역 안 콘텐츠다 —
        // 페이지 흐름 블록으로 방출하면 각주 밖에 그려진다 (#94). 표 셀과 같은
        // 수집기를 쓰되 표까지 담는다: 셀은 `PlacedCellContent.nestedTables`가
        // 따로 배치하지만 각주에는 그 경로가 없다.
        let collector = HwpParagraphObjectCollector(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: noteResolver,
            collectsTextboxes: true,
            attributeCache: attributeCache,
            collectsTables: true
        )
        let objects = collector.objects(
            in: paragraph,
            frame: measured.frame,
            paragraphRect: Self.paragraphRect(
                width: width, textHeight: measured.frame.totalHeight
            ),
            numbering: numbering,
            // 문단 높이가 줄 캐시면 표는 캐시 마지막 줄 상자 안에 들어야 한다 (#214 리뷰) — 각주 끝
            // 블록은 그 줄의 줄 간격을 빼고 쌓는다 (`stackingHeight`).
            tableContainmentBottom: measured.cachedLineExtent.map {
                HwpUnits.points(fromHwpUnit: Int32(clamping: $0.bottom - $0.top))
            }
        )
        // 쪽에 걸친 문단 (세로 위치 리셋) 은 `cachedLineExtent`가 거부해 CT 높이로
        // 떨어진다 — 쪽 몫의 합이 한글 높이다 (#165). 단조 캐시는 두 산식이 같다.
        //
        // **개체를 담은 각주는 예외다** (#165 리뷰): 그 합은 한글이 **두 쪽에 나눠** 그린
        // 높이인데 개체를 담은 각주는 나누지 않고 한 쪽에 통째로 그리므로
        // (`carriesObjects`), 그 합으로 낮추면 CT 좌표로 수집한 개체를 블록이 담지 못해
        // 다음 각주와 겹친다 (실측: 블록 44.16pt에 개체 하단 79.35pt). 개체를 놓은
        // 좌표계인 CT 높이를 그대로 두고, 그 높이엔 없는 캐시 마지막 줄 간격 대신 **CT 프레임의**
        // 마지막 줄 상자 아래 몫을 뺀다 — 캐시 없는 각주와 같은 규칙이다 (#222 리뷰: 0을 두면 같은
        // 각주가 낡은 캐시 한 줄이 붙었다는 이유만으로 스택이 6pt 커졌다). 떠 있는 개체는
        // `stackingHeight`의 `floatingBottom` 하한이 지킨다.
        var frame = measured.frame
        // 줄 캐시가 없는 각주(흐름 조판 문서·캐시를 버린 HWPX)는 CT 프레임의 상자 아래 몫
        // (`stackTrailingGap` — 줄 간격 여분 + 문단 아래 간격)을 뺀다 (#222) — 한글은 캐시 유무와
        // 무관하게 각주 스택을 마지막 줄 **상자**까지로 쌓는다 (한글 12.30 실측 `probes/222` FN:
        // 10pt·160% 각주 한 줄의 상자 바닥이 본문 하단에 닿고 영역은 위 8.5 + 구분선 아래 5.67 +
        // 상자 10 = 24.17). 종전 0은 그 여분 6pt만큼 영역을 키워 구분선이 위로 올라가고 본문이
        // 그만큼 먼저 넘어갔다.
        var trailingSpacing = cacheLines.map {
            HwpFootnoteCacheLines.trailingSpacing(of: $0, in: $0.indices)
        } ?? Self.stackTrailingGap(of: measured)
        let carriesObjects = noteCarriesObjects || Self.carriesObjects(objects)
        if let cacheLines, measured.cachedLineExtent == nil {
            if carriesObjects {
                trailingSpacing = Self.stackTrailingGap(of: measured)
            } else {
                frame = HwpParagraphFrame(
                    totalHeight: HwpFootnoteCacheLines.height(
                        of: cacheLines, in: cacheLines.indices
                    ),
                    lines: frame.lines
                )
            }
        }
        return NoteMeasurement(
            totalHeight: frame.totalHeight,
            text: LazyText(attributed: measured.attributed, lines: frame.lines),
            objects: objects,
            sourceAttributed: measured.attributed,
            sourceLines: measured.frame.lines,
            cacheLines: cacheLines,
            placedLineCount: 0,
            placedLength: 0,
            carriesObjects: carriesObjects,
            trailingLineSpacing: trailingSpacing,
            sourceWidth: width,
            sourceLayout: nil
        )
    }

    /// CT로 잰 각주 문단의 스택에서 빼는 몫 (#222) — 전진량 끝(프레임 높이 − 문단 위 간격)에서
    /// **모든 줄 상자 아래의 최댓값**까지. 줄 캐시 쪽 규약(①, `HwpFootnoteCacheLines.trailingSpacing`
    /// — "전진량 끝 최댓값 − 상자 아래 최댓값")과 같은 정의다: 고정 줄 간격이 앞 줄 상자보다 작으면
    /// 앞 줄(30pt 글자·글자처럼 취급 개체)이 마지막 줄 아래로 내려가므로, 마지막 줄만 보는
    /// `HwpParagraphMeasurer.Result.trailingGap`(컨테이너 내용 범위의 규칙 #193)을 빼면 그 줄이
    /// 스택 밖으로 나간다 (#222 PR 리뷰: 30pt 개체 줄 + 10pt 줄·고정 16pt → 32 − 6 = 26에 개체
    /// 30이 담기지 않았다 — 글자처럼 취급 개체는 `floatingBottom`으로도 지켜지지 않는다). 줄이
    /// 고르면 마지막 줄의 몫과 같고, 상자가 프레임 아래로 나가는 줄(전진량 < 상자)은 **음수**라
    /// 스택이 그 상자 바닥까지 자란다 (#222 PR 리뷰 — 한글 12.30 실측 so222n NF: 고정 8pt 두 줄
    /// 각주의 마지막 줄 상자 바닥이 본문 하단에 닿는다; 0으로 자르면 상자가 2pt 밖으로 나갔다).
    /// 한글이 저장한 그런 각주는 줄 캐시의 줄 간격이 음수라 `HwpFootnoteCacheLines.lines`가 받지
    /// 않고 이 CT 경로로 온다.
    /// 배치(`measureNote`)와 예약의 빠른 길(`HwpFootnoteCoordinator.measuredFootnoteTextHeight`)이
    /// 이 함수를 함께 쓴다.
    static func stackTrailingGap(of measured: HwpParagraphMeasurer.Result) -> CGFloat {
        let lines = measured.frame.lines
        guard let last = lines.last else { return measured.trailingGap }
        let lastBottom = last.origin.y + max(0, last.boxHeight)
        let lowestBottom = lines.reduce(lastBottom) { max($0, $1.origin.y + max(0, $1.boxHeight)) }
        return measured.trailingGap - (lowestBottom - lastBottom)
    }

    /// 이어지는 조각의 측정 — 원본 조판에서 앞 쪽에 실린 줄 뒤를 잘라 내고 높이는 그 줄들의
    /// 캐시 합이다 (원본에 실린 누적표로 한 번에). 개체는 첫 조각 몫이라 수집하지 않는다.
    private static func continuationMeasurement(
        layout: SourceLayout,
        placedLineCount: Int,
        placedLength: Int,
        noteCarriesObjects: Bool
    ) -> NoteMeasurement {
        let cacheLines = layout.cacheLines
        let range = min(placedLineCount, cacheLines.count) ..< cacheLines.count
        return NoteMeasurement(
            totalHeight: layout.remainingHeight(from: range.lowerBound),
            text: LazyText {
                let fragment = fragment(
                    of: layout.attributed, lines: layout.lines,
                    cacheLineCount: cacheLines.count, cacheRange: range,
                    startingAt: placedLength
                )
                return (fragment.attributed, fragment.lines)
            },
            objects: HwpParagraphObjectCollector.Objects(),
            sourceAttributed: layout.attributed,
            sourceLines: layout.lines,
            cacheLines: cacheLines,
            placedLineCount: placedLineCount,
            placedLength: placedLength,
            carriesObjects: noteCarriesObjects,
            trailingLineSpacing: HwpFootnoteCacheLines.trailingSpacing(of: cacheLines, in: range),
            sourceWidth: layout.width,
            sourceLayout: layout
        )
    }

    /// 각주 문단의 글자처럼 취급 표가 수집기(`HwpParagraphObjectCollector.table`)에서 그려질 높이
    /// (controlIndex → pt, #214) — 줄 예약과 캐시 신선도 판정(`HwpParagraphLayout.lineCacheIsStale`)이
    /// 같이 쓴다.
    private func inlineTableHeights(
        of paragraph: CoreHwp.HwpParagraph,
        width: CGFloat,
        index: HwpIndex,
        resolver: HwpObjectSizeResolver?,
        numbering: HwpNumberingScope?
    ) -> [Int: CGFloat] {
        HwpTableLayout(fontResolver: fontResolver, attributeCache: attributeCache)
            .inlineTableHeights(
                in: paragraph, availableWidth: width, index: index,
                sizeResolver: resolver, numbering: numbering
            )
    }

    /// 이 각주가 그릴 개체가 있는지 — 쪽 끝 분할 금지·CT 높이 보존 술어 (#165 리뷰).
    static func carriesObjects(_ objects: HwpParagraphObjectCollector.Objects) -> Bool {
        objects.count > 0 || objects.floatingBottom != nil
    }
}
