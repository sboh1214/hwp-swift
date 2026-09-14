import CoreGraphics
import CoreText
import Foundation

// 글자 위치(표 33)로 옮겨진 글리프와 **기하 질의** (#197 리뷰).
//
// 조판 문자열은 `kCTBaselineOffset`을 싣지 않으므로(한글처럼 줄 상자를 안 키우려고)
// CT가 대신 rect를 부풀려 주지 않는다 — 옮겨진 잉크를 덮어야 하는 쪽이 직접 걷는다.

public extension HwpDrawnLine {
    /// 잉크가 실제로 닿는 범위 — 줄 상자(`selectionRect`) **+ 옮겨진 run마다 그 run의
    /// 잉크 가로 범위만** 가진 밴드 (top-down 페이지 좌표).
    ///
    /// "이 지점에 글자가 칠해졌는가"(claim)와 "링크를 눌렀는가"(히트)는 **옮겨진
    /// 글리프**를 따라야 한다 — 안 그러면 보이는 글자를 눌러도 링크가 안 열린다
    /// (실측: Helvetica 10pt 링크에 글자 위치 30이면 잉크 하단 3.000pt가 줄 상자 밖이라
    /// 하단 클릭이 `.text`로 떨어지고, 위치 100에서는 겹침이 0%가 된다).
    ///
    /// **하나의 rect로 합치지 않는다** (#197 리뷰 2차): 줄 전체 폭에 최대 오프셋을 걸면
    /// 안 옮겨진 run 아래의 **빈 공간까지 칠한 것으로 claim**해, 그 자리의 탭이 뒤 층의
    /// 보이는 링크를 막는다 ('ABBBBBBBBBB'에서 A만 10pt 내리면 B 아래 빈 띠가 그렇다).
    /// claim은 정밀 커버리지여야 한다는 규약(R54) 그대로다.
    var paintedRects: [CGRect] {
        paintedRects(bands: HwpDrawnTextLayout.glyphOffsetBands(of: line))
    }
}

extension HwpDrawnLine {
    /// 밴드를 이미 걷어 둔 호출자용 (`HwpDrawnTextLayout.glyphOffsetBands(ofLines:in:)`).
    func paintedRects(bands: [HwpDrawnTextLayout.GlyphOffsetBand]) -> [CGRect] {
        let box = selectionRect
        var rects = [box]
        for band in bands {
            let x = baselineOrigin.x + band.minX
            let width = band.maxX - band.minX
            guard width > 0 else { continue }
            rects.append(CGRect(
                x: x, y: box.minY - band.offset, width: width, height: box.height
            ))
        }
        return rects
    }
}

extension HwpDrawnTextLayout {
    /// 옮겨진 run 하나의 잉크 가로 범위(줄 원점 기준)와 그 오프셋.
    struct GlyphOffsetBand {
        let minX: CGFloat
        let maxX: CGFloat
        /// 렌더러 규약 그대로 **양수 = 위**.
        let offset: CGFloat
        /// 이 밴드를 낸 run들의 문자열 범위 — **CTLine 인덱스**다 (재조판된 부분 복사본
        /// 기준). 링크 스팬이 자기 run의 밴드만 가려낼 때 쓴다 (#197 리뷰 4차). 시각적으로
        /// 잇닿은 같은 오프셋·같은 링크의 run이 한 밴드로 묶이므로 (#200 리뷰) 여럿일 수 있다.
        let ranges: [CFRange]

        /// 이 밴드의 run이 **전부** `span` 안에 통째로 드는가 (CTLine 인덱스끼리 비교).
        ///
        /// 교집합이 아니라 **포함**으로 묻는다: CT는 속성이 바뀌는 자리마다 run을
        /// 끊으므로 (실측: `abc אבג`에 링크 둘을 걸면 run이 ct[0,3)·[3,4)·[5,7)·[4,5)로
        /// 정확히 갈린다) 정상적으로는 둘이 같지만, 혹시라도 run이 두 스팬에 걸치면
        /// 포함이 실패해 **남의 잉크를 안 가져간다**.
        func belongs(to span: CFRange) -> Bool {
            ranges.allSatisfy { range in
                range.location >= span.location
                    && range.location + range.length <= span.location + span.length
            }
        }
    }

    /// 줄별 밴드 — 링크 스팬·줄마다 다시 걷지 않게 호출자가 한 번만 받아 나눠 쓴다.
    ///
    /// 글자 위치 run이 **하나도 없는** 문단(대다수)은 CTRun 전수 순회 자체를 건너뛴다:
    /// `CTRunGetAttributes`는 run마다 CFDictionary를 브리징해 오프셋이 없어도 값을
    /// 치른다. 속성 run 한 번 훑기가 훨씬 싸다.
    static func glyphOffsetBands(
        ofLines drawnLines: [HwpDrawnLine], in attributedString: NSAttributedString
    ) -> [[GlyphOffsetBand]] {
        guard carriesGlyphOffset(attributedString) else {
            return Array(repeating: [], count: drawnLines.count)
        }
        return drawnLines.map { glyphOffsetBands(of: $0.line) }
    }

    /// 조판 문자열의 가장 큰 글자 위치 |오프셋| — 자격 영역(`HwpHitTester.textBounds`)이
    /// 옮겨진 밴드를 품도록 줄 높이에 더하는 몫이다 (#200 리뷰). `carriesGlyphOffset`과
    /// 같은 술어(`offset != 0`)를 쓰되 조판 없이 속성 run만 훑는다.
    static func maxGlyphOffsetMagnitude(in attributedString: NSAttributedString) -> CGFloat {
        var magnitude: CGFloat = 0
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.glyphBaselineOffset,
            in: NSRange(location: 0, length: attributedString.length),
            options: .longestEffectiveRangeNotRequired
        ) { value, _, _ in
            guard let offset = (value as? NSNumber)?.doubleValue, offset != 0 else { return }
            magnitude = max(magnitude, CGFloat(abs(offset)))
        }
        return magnitude
    }

    /// 조판 문자열에 0이 아닌 글자 위치 run이 하나라도 있는가.
    private static func carriesGlyphOffset(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.glyphBaselineOffset,
            in: NSRange(location: 0, length: attributedString.length),
            options: .longestEffectiveRangeNotRequired
        ) { value, _, stop in
            guard let offset = (value as? NSNumber)?.doubleValue, offset != 0 else { return }
            found = true
            stop.pointee = true
        }
        return found
    }

    /// 옮겨진 run마다 (줄 원점 기준 가로 범위, 오프셋) — 정밀 커버리지용.
    ///
    /// 가로 범위는 **잉크 경계**(`CTRunGetImageBounds`, 줄 원점 기준)에서 낸다 — claim은
    /// 칠한 자리만 가져가야 하고(R54) 밴드는 그 run이 실제로 찍은 잉크의 세로 이동분이기
    /// 때문이다 (#200 리뷰). 진행 폭 기반은 두 가지로 틀렸다 (2026-09-14 실측, Helvetica 10pt):
    /// - **잉크 없는 진행 폭을 덮는다** — 꼬리 공백은 줄 상자(`selectionRect`)가 빼는데 밴드는
    ///   품어 `LINK   `의 밴드가 22.2가 아니라 30.6까지 갔고, 공백뿐인 run(줄 상자 폭 0)이
    ///   8.3 폭의 밴드를 냈으며, 탭(글자 모양 속성으로 방출된다)의 21.3 진행 폭도 들어갔다.
    ///   그 빈 띠가 링크로 눌리고, 전경 글자가 뒤 층의 보이는 링크를 거짓으로 가린다.
    /// - **장평(글꼴 매트릭스)이 반영되지 않는다** — `CTRunGetPositions`는 매트릭스 **적용
    ///   전** 좌표(0…22.2)를 주고 `CTRunGetTypographicBounds`는 적용 후 폭(12.5)을 주므로,
    ///   장평 50% run의 밴드가 줄 머리에서는 실제 잉크(0.4…11.1)의 두 배였고 줄 중간에서는
    ///   엉뚱한 열 위에 섰다(실제 x = a × position). 이미지 경계는 적용 후다.
    ///
    /// 문자열 인덱스로 되짚지 않는 이유는 그대로다 — 재조판된 부분 복사본에서 범위가
    /// 어긋나고 RTL은 논리 순서와 x 순서가 반대다. 잉크 경계는 시각 좌표라 둘 다 무관하다.
    ///
    /// **낱말 사이는 줄 상자와 같은 기준으로 덮는다**: 시각 순서(`CTLineGetGlyphRuns`가 주는
    /// 순서)로 잇닿은 **같은 오프셋·같은 링크**의 run을 한 밴드로 묶고, 그 사이에 낀 잉크 없는
    /// run(공백·탭)은 진행 폭(`CTLineGetOffsetForStringIndex`, 매트릭스 적용 후)으로 다리를
    /// 놓는다. run 하나 안의 공백만 품으면 폰트 폴백·글자 모양·스크립트 슬롯이 run을 가르는
    /// 자리(`홈페이지 바로가기`는 [홈페이지][ ][바로가기] 세 run이고 `CharShape` 픽스처의
    /// '글자위치 30' 줄도 HCRBatang 세 run)마다 옮겨진 링크의 낱말 사이가 히트 불가가 되고
    /// claim에 구멍이 나 뒤 층 링크가 열린다 (#200 리뷰 검증: 7.24pt 구멍). 묶음의 앞뒤 잉크
    /// 없는 run은 버린다 — 꼬리·머리 공백과 공백뿐인 묶음은 밴드가 없다. 개체 run
    /// (run delegate)은 옮겨지지 않으므로(개체 명령이 따로 그린다) 묶음을 끊는다.
    /// 합성 볼드의 stroke 확장·그림자 사본·양각 사본은 이미지 경계에 안 든다 (≤0.4pt·
    /// 그림자 오프셋·±0.7pt) — 줄 상자도 그것을 안 덮는 기존 격차라 밴드도 같은 기준이다.
    static func glyphOffsetBands(of line: CTLine) -> [GlyphOffsetBand] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var bands: [GlyphOffsetBand] = []
        var group: GlyphOffsetBandGroup?
        func close() {
            if let band = group?.band() {
                bands.append(band)
            }
            group = nil
        }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            guard let offset =
                (attributes?[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber)?.doubleValue,
                offset != 0,
                attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] == nil
            else {
                close()
                continue
            }
            let url = attributes?[HwpAttributedStringKey.hyperlink] as? String
            if group?.offset != CGFloat(offset) || group?.url != url {
                close()
                group = GlyphOffsetBandGroup(offset: CGFloat(offset), url: url)
            }
            // nil 컨텍스트면 줄 원점(CGPointZero) 기준 — `drawEmphasisIfNeeded`와 같은 호출.
            let ink = CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0))
            let range = CTRunGetStringRange(run)
            group?.members.append(GlyphOffsetBandGroup.Member(
                range: range,
                ink: ink.isNull || ink.width <= 0 ? nil : ink,
                advance: {
                    let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
                    let end = CTLineGetOffsetForStringIndex(
                        line, range.location + range.length, nil
                    )
                    return min(start, end) ... max(start, end)
                }
            ))
        }
        close()
        return bands
    }
}

/// 시각적으로 잇닿은 같은 오프셋·같은 링크의 run 묶음 — 밴드 하나가 된다.
private struct GlyphOffsetBandGroup {
    struct Member {
        let range: CFRange
        /// 잉크 경계 (줄 원점 기준). 잉크가 없으면 nil (공백·탭).
        let ink: CGRect?
        /// 진행 폭 범위 — 잉크 없는 run이 묶음 **안쪽**에 낄 때만 평가한다.
        let advance: () -> ClosedRange<CGFloat>
    }

    let offset: CGFloat
    let url: String?
    var members: [Member] = []

    /// 앞뒤의 잉크 없는 run을 버리고, 남은 구간의 잉크(없으면 진행 폭)를 합친다.
    func band() -> HwpDrawnTextLayout.GlyphOffsetBand? {
        guard let first = members.firstIndex(where: { $0.ink != nil }),
              let last = members.lastIndex(where: { $0.ink != nil })
        else { return nil }
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        for member in members[first ... last] {
            if let ink = member.ink {
                minX = min(minX, ink.minX)
                maxX = max(maxX, ink.maxX)
            } else {
                let advance = member.advance()
                minX = min(minX, advance.lowerBound)
                maxX = max(maxX, advance.upperBound)
            }
        }
        guard maxX > minX else { return nil }
        return HwpDrawnTextLayout.GlyphOffsetBand(
            minX: minX, maxX: maxX, offset: offset,
            ranges: members[first ... last].map(\.range)
        )
    }
}
