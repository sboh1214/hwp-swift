import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 변경 추적 (PARA_RANGE_TAG kind 16/17)과 메모 (댓글) 앵커 범위 마킹.
extension HwpTextRunBuilder {
    /// PARA_RANGE_TAG의 변경 추적 마크 (16 삽입 / 17 삭제)를 한글.app처럼
    /// 표시한다: 삽입 = 빨강 글자 + 빨강 밑줄, 삭제 = 빨강 글자 + 빨강 취소선.
    func applyTrackChangeMark(
        _ mark: UInt32,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard mark == 16 || mark == 17 else { return }
        let red = CGColor.hwpTrackChange
        attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = red
        if mark == 17 {
            // 삭제선은 일반 취소선과 같은 자리·두께다 (#187 실측: 한글 문서 +0.35em,
            // MS 워드 호환 문서는 글꼴 지표 — 둘 다 일반 취소선 경로가 가른다). 모양은 늘
            // 실선 — 글자 모양의 물결·점선 취소선(`strikethroughShape`, #191)이 남으면 삭제
            // 표시까지 그 모양으로 그려진다 (PR 리뷰; 삽입 밑줄도 렌더러가 실선으로 못박는다).
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = red
            attributes.removeValue(forKey: HwpAttributedStringKey.strikethroughShape)
        } else {
            // 삽입 밑줄도 일반 '글자 아래' 밑줄과 같은 자리·두께다 — 색만 이 키로
            // 넘긴다 (글자 모양의 밑줄 색과 별개라 밑줄 키에 실을 수 없다).
            attributes[HwpAttributedStringKey.trackInsertUnderline] = red
        }
    }

    /// 변경 추적 range tag 한 구간 — WCHAR 스트림 위치 `[start, end)`와 kind (16 삽입 / 17 삭제).
    typealias TrackChangeInterval = (start: UInt32, end: UInt32, kind: UInt32)

    /// 변경 추적 range tag (kind 16 삽입 / 17 삭제)를 시작 위치 오름차순으로
    /// 정렬해 돌려준다. 문자 루프에서 단조 커서로 sweep하기 위한 것으로,
    /// 문자마다 전체 배열을 다시 스캔하는 O(문자×태그)를 없앤다 (#11).
    static func trackChangeIntervals(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [TrackChangeInterval] {
        (paragraph.paraRangeTagArray ?? []).compactMap { tag in
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { return nil }
            return (start: tag.start, end: tag.end, kind: kind)
        }
        .sorted { $0.start < $1.start }
    }

    /// position (원본 WCHAR 스트림 위치)이 속한 변경 추적 range tag의 kind.
    /// 16 (삽입)/17 (삭제) 외의 태그는 무시한다.
    static func trackChangeMark(
        at position: UInt32,
        in paragraph: CoreHwp.HwpParagraph
    ) -> UInt32 {
        for tag in paragraph.paraRangeTagArray ?? [] {
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { continue }
            if position >= tag.start, position < tag.end {
                return kind
            }
        }
        return 0
    }

    /// 메모 (댓글) 필드가 감싸는 앵커 텍스트의 WCHAR 스트림 범위.
    /// extended 컨트롤 문자 (필드 시작, ctrl 순서 = ctrlHeaderArray 순서)부터
    /// 다음 필드 끝 inline 문자 (코드 4)까지.
    static func memoAnchorRanges(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [Range<UInt32>] {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.contains(where: {
                  if case .memo = $0 {
                      true
                  } else {
                      false
                  }
              })
        else { return [] }
        // 필드는 코드 3 시작 ~ 코드 4 끝으로 LIFO 중첩된다 — 필드 depth와
        // depth별 memo 스택으로 매칭 종결자에서만 닫아, memo 안 중첩 필드
        // (하이퍼링크 등)의 끝 마커가 바깥 앵커를 조기 종료하거나 중첩 memo가
        // 바깥 start를 덮지 않게 한다 (HwpTextRunBuilder 하이퍼링크 스택과 동일, #2).
        var ranges: [Range<UInt32>] = []
        var position: UInt32 = 0
        var ordinal = 0
        var fieldDepth = 0
        var memoStack: [(depth: Int, start: UInt32)] = []
        for hwpChar in paragraph.paraText?.charArray ?? [] {
            let length: UInt32 = hwpChar.type == .char ? 1 : 8
            if hwpChar.type == .extended {
                if hwpChar.value == 3 {
                    fieldDepth += 1
                    if ordinal < ctrls.count, case .memo = ctrls[ordinal] {
                        memoStack.append((depth: fieldDepth, start: position + length))
                    }
                }
                ordinal += 1
            } else if hwpChar.type == .inline, hwpChar.value == 4 {
                if let top = memoStack.last, top.depth == fieldDepth {
                    if position > top.start {
                        ranges.append(top.start ..< position)
                    }
                    memoStack.removeLast()
                }
                if fieldDepth > 0 {
                    fieldDepth -= 1
                }
            }
            position += length
        }
        // 빌더의 단조 sweep은 lowerBound 오름차순을 전제한다 — 중첩 close 순서
        // (안쪽 먼저)로 어긋난 정렬을 복원한다.
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}

/// 조판 문자열 생성 보조 (메모 앵커 sweep·문자별 방출 텍스트).
extension HwpTextRunBuilder {
    /// 변경 추적 구간 커서를 `position`까지 앞으로만 밀고 그 자리의 kind를 준다
    /// (16 삽입 / 17 삭제, 구간 밖 0 — `memoAnchor(at:in:cursor:)`와 같은 sweep 규약).
    func trackMark(
        at position: UInt32,
        in intervals: [TrackChangeInterval],
        cursor: inout Int
    ) -> UInt32 {
        while cursor < intervals.count, intervals[cursor].end <= position {
            cursor += 1
        }
        return cursor < intervals.count && intervals[cursor].start <= position
            && position < intervals[cursor].end ? intervals[cursor].kind : 0
    }

    /// 메모 앵커 구간 커서를 `position`까지 앞으로만 밀고 포함 여부를 준다
    /// (`build`의 sweep 규약 — position은 단조 증가한다).
    func memoAnchor(
        at position: UInt32,
        in ranges: [Range<UInt32>],
        cursor: inout Int
    ) -> Bool {
        while cursor < ranges.count, ranges[cursor].upperBound <= position {
            cursor += 1
        }
        return cursor < ranges.count && ranges[cursor].contains(position)
    }

    /// 글자가 하나도 없는 문단의 조판 문자열 — **빈 문단 앵커**. 문단의 첫 글자
    /// 모양으로 빈칸 하나를 만들고 빈 줄 앵커와 같은 표식·허용 목록
    /// (`finishEmptyLastLineAnchor`: 글꼴·`baseFontSize`만, 장식 없음)을 적용한 뒤
    /// 같은 paraShape의 문단 스타일을 붙인다.
    ///
    /// 빈 문단이 조판 문자열을 갖는 이유 (#145): 길이 0이면
    /// `HwpBlockContentWalker`가 단위를 내지 않아 선택·복사에서 그 줄이 빠지고
    /// (`A / 빈 문단 / B`를 복사하면 `A\n\nB`가 아니라 `A\nB`), 캐럿도 놓이지
    /// 않는다. 빈칸 1자면 단위·조각·캐럿·히트가 무수정으로 빈 줄을 다루고, 복사는
    /// 빈 줄 앵커와 같은 판정(`droppingEmptyLineAnchor`)으로 글자를 떼되 그 문단을
    /// 종결하는 개행에 앵커의 문단 스타일·글꼴을 실어 서식이 RTF에 남는다.
    ///
    /// 높이 산식은 종전 측정 대역과 같다 — 이 문자열을 `HwpParagraphLayout.layout`에
    /// 넣으면 줄 간격 종류(비율·고정·최소·여백만), 강제 줄 높이 클램프, 문단
    /// 위/아래 간격이 실제 문단과 **같은 코드로** 계산된다. 다만 측정 셋
    /// (`HwpParagraphMeasurer`·`HwpPaginator.layout`·`HwpPageChromeBuilder`)은
    /// 높이만 취하고 줄 프레임은 비워 둔다 — 표 절단·다단 재분배·줄 중간 앵커가
    /// 라인 유무로 갈리므로 페이지네이션 결과를 접기 전과 같게 두기 위해서다.
    ///
    /// 소비자별 가드: 복사 `droppingEmptyLineAnchor`(글자 제거)·검색
    /// `HwpTextSearcher`(앵커 전용 단위 제외)·낭독 `accessibilityLabel`(공백만
    /// 남으면 버림)·페인트(빈칸은 잉크가 없고 장식은 허용 목록으로 떨어짐).
    ///
    /// MS 워드 호환 문서(#194)에서는 앵커를 **라틴 슬롯** 글꼴로 조판한다 — 빈 문단의 줄
    /// 상자는 문단 끝 글자(CR)뿐이고 한글은 그 글자를 라틴 슬롯 글꼴로 세운다 (한글 12.30
    /// 실측 2026-09-20 `cm194-mixed`: 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo
    /// 10pt 글자 모양의 빈 문단 `vertsize` 1515·`baseline` 1104 = Menlo, 20pt 3029·2207;
    /// 함초롬돋움 1692·1266). 한글 문서의 줄 상자는 글꼴과 무관하므로 종전대로 한글 슬롯이다.
    func emptyParagraphAnchor(for paragraph: CoreHwp.HwpParagraph) -> NSMutableAttributedString {
        let shapeId = paragraph.paraCharShape.shapeId.first ?? 0
        let shape = index.charShape(id: shapeId) ?? CoreHwp.HwpCharShape()
        let script: HwpScript = index.compatibleDocumentTarget == .msWord ? .english : .korean
        let anchor = NSMutableAttributedString(
            string: " ",
            attributes: attributes(for: shape, script: script)
        )
        finishEmptyLastLineAnchor(in: anchor, emitted: true)
        attachParagraphStyle(to: anchor, paragraph: paragraph)
        return anchor
    }

    /// `build`의 마무리 — 문단 스타일을 붙여 돌려주되, 잘리지 않은 문단이 아무
    /// 글자도 내지 않았으면(PARA_TEXT 없음·빈 배열·문단 끝(13)·하이픈(24)뿐인 HWPX
    /// 빈 문단) 빈 문단 앵커로 바꾼다 (#145). 세 형태의 조판 문자열이 같아야 두
    /// 포맷의 빈 문단이 같게 선택·복사된다. 상한으로 잘린 결과(`whole == false`,
    /// 메모 표시 예산)는 빈 채로 둔다 — 잘린 문단이 빈 줄 하나로 보이면 안 된다.
    ///
    /// `bodyStart`부터 끝까지는 본문 글자다 — 빈칸 폭(`applySpaceWidths`)을 여기서 준다.
    func finishBuild(
        _ output: NSMutableAttributedString,
        paragraph: CoreHwp.HwpParagraph,
        whole: Bool,
        bodyStart: Int? = nil
    ) -> NSAttributedString {
        if let bodyStart, bodyStart < output.length {
            applySpaceWidths(
                to: output, in: NSRange(location: bodyStart, length: output.length - bodyStart)
            )
        }
        if output.length == 0, whole {
            let anchor = emptyParagraphAnchor(for: paragraph)
            attachParagraphEndBaseFontSize(to: anchor, paragraph: paragraph)
            return anchor
        }
        attachParagraphStyle(to: output, paragraph: paragraph)
        if whole {
            attachParagraphEndBaseFontSize(to: output, paragraph: paragraph)
            attachMsWordParagraphEndBox(to: output, paragraph: paragraph)
        }
        return output
    }

    /// 조판 문자열이 빈 문단 앵커 **하나뿐**인지 — 빈 줄 앵커(`가\n `)는 언제나
    /// 한 줄 끝 뒤에 오므로 길이가 2 이상이라 갈린다. 측정 셋이 줄 프레임을
    /// 비우는 술어이고, 검색이 앵커 전용 단위를 거르는 술어이며, 복사가 빈
    /// 문단의 선택 포함 규칙을 가르는 술어다.
    static func isEmptyParagraphAnchor(_ attributed: NSAttributedString) -> Bool {
        attributed.length == 1
            && attributed.attribute(
                HwpAttributedStringKey.emptyLineAnchor, at: 0, effectiveRange: nil
            ) != nil
    }

    /// 빈 줄 앵커가 유지하는 속성 — 빈 줄의 **높이**를 정하는 것만 남긴다.
    /// 허용 목록인 이유는 장식 키가 늘어도 앵커가 새 장식을 물려받지 않게
    /// 하기 위해서다 (아래 장식 항목 참조).
    static let emptyLastLineAnchorAttributes: [NSAttributedString.Key] = [
        kCTFontAttributeName as NSAttributedString.Key,
        HwpAttributedStringKey.baseFontSize,
        // 문서 단위 표식은 남긴다 — MS 워드 호환 줄 상자 판정이 run 단위라 앵커만 있는
        // 줄도 갈래를 알아야 한다 (#187).
        HwpAttributedStringKey.compatibleDocumentTarget,
    ]

    /// 빈 줄 앵커 run을 표식하고 장식 속성을 떼어 낸다. `build`가 앵커를 실제로
    /// 방출했을 때만 부른다 — 앵커는 언제나 문단의 **마지막** 문자다. 빈 문단
    /// 앵커(`emptyParagraphAnchor`)도 같은 표식·허용 목록을 쓴다.
    ///
    /// **글자만 보고 판정하지 않는다.** 앵커는 빈칸이라 `가 + LF + 빈칸 + CR`가
    /// 내는 **사용자 입력 빈칸**과 조판 문자열이 완전히 같다(둘 다 `가 + LF +
    /// 빈칸`). 꼬리 문자열로 판정하면 후자의 진짜 빈칸에 걸린 변경 추적·밑줄·
    /// 음영·메모 강조까지 함께 떨어진다. 그래서 방출 시점의 사실
    /// (`emittedText`의 `emittedAnchor`)만 믿고, 표식은
    /// `HwpAttributedStringKey.emptyLineAnchor`로 남겨 복사 경로가 같은 판정을
    /// 다시 할 수 있게 한다.
    ///
    /// 장식을 떼는 이유: 앵커는 잉크가 없지만 **장식은 글리프가 아니라 run
    /// 폭에 그려진다** — `HwpPageLayerDecorations.runBounds`가
    /// `CTRunGetTypographicBounds`를 쓰고 그 값은 후행 공백을 포함하므로,
    /// 마지막 글자 모양에 음영·밑줄·취소선이 걸려 있으면 앵커만 있는 빈 줄에
    /// 0.5em짜리 장식 토막이 그려진다 (합성 실측: 접기 전 0.000 → 앵커 도입 후
    /// 5.000). 형광펜을 칠한 문단을 Shift+Enter로 끝내면 바로 나오는 형태다.
    ///
    /// MS 워드 호환 문서(#194)에서는 앵커의 글꼴을 `paragraph`의 마지막 글자 모양의 **라틴
    /// 슬롯** 글꼴(`msWordParagraphEndFont`)로 바꾼다 — 빈 줄 앵커는 문단 끝 글자(CR)의
    /// 자리이고 한글은 그 글자를 라틴 슬롯 글꼴로 줄 상자에 세우므로, 앞 글자의 한글 슬롯
    /// 글꼴을 물려받으면 그 줄 상자가 한글 슬롯 상자만큼 커진다 (`emptyParagraphAnchor`의
    /// 실측과 같은 규칙). 한글 문서·`paragraph` 없음이면 글꼴은 그대로다.
    func finishEmptyLastLineAnchor(
        in output: NSMutableAttributedString, emitted: Bool,
        paragraph: CoreHwp.HwpParagraph? = nil
    ) {
        guard emitted, output.length > 0 else { return }
        let latinSlotFont = paragraph.flatMap { msWordParagraphEndFont(of: $0) }
        let range = NSRange(location: output.length - 1, length: 1)
        let existing = output.attributes(at: range.location, effectiveRange: nil)
        var kept: [NSAttributedString.Key: Any] = [
            HwpAttributedStringKey.emptyLineAnchor: true,
        ]
        for key in Self.emptyLastLineAnchorAttributes {
            kept[key] = existing[key]
        }
        if let latinSlotFont {
            kept[kCTFontAttributeName as NSAttributedString.Key] = latinSlotFont
        }
        output.setAttributes(kept, range: range)
    }

    /// MS 워드 호환 문서에서 문단 끝 글자(CR)가 서는 글꼴 — 마지막 글자 모양의 라틴 슬롯
    /// 글꼴 (#187·#194). 한글 문서·글자 모양 없음이면 nil.
    func msWordParagraphEndFont(of paragraph: CoreHwp.HwpParagraph) -> CTFont? {
        guard index.compatibleDocumentTarget == .msWord,
              let shapeId = paragraph.paraCharShape.shapeId.last
        else { return nil }
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)
        // 캐시 경로 — 같은 글자 모양의 라틴 슬롯 사전은 본문 run이 이미 만들어 두었다.
        let attributes = attributes(for: resolved, script: .english)
        guard let value = attributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        return (value as! CTFont) // swiftlint:disable:this force_cast
    }

    /// 이 문자가 조판 문자열에 낼 텍스트.
    ///
    /// 문단 끝(13)은 `controlText`가 접지만, **한 줄 끝(10) 바로 뒤**에서는 빈 줄
    /// 앵커로 빈칸(U+0020)을 낸다. CoreText는 하드 개행 뒤에 내용이 있어야 그 줄을
    /// 만들기 때문이다 — `"가\n"`은 한 줄이고 `"가\n<무언가>"`가 두 줄이다. 앵커
    /// 없이 접으면 한글이 라인 캐시에 배정해 둔 마지막 빈 줄이 사라져, 캐시를
    /// 쓰지 않는 측정 경로(글상자·캐시 무효 문단·안전밸브로 linesegarray를 폐기한
    /// HWPX 문단)에서 문단 높이가 한 줄만큼 짧아진다 (실측:
    /// `legacy-common-control-property` Section9의 407 WCHAR 문단, 폭 400에서
    /// 접기 전 9줄 144pt → 앵커 없이 접으면 8줄 128pt → 앵커를 넣으면 다시
    /// 9줄 144pt).
    ///
    /// **앵커를 U+000D로도 U+200B로도 두지 않는다.** U+000D를 남기면 #137이 고친
    /// 조판 부호가 그 빈 줄에 그대로 다시 그려진다. U+200B는 잉크가 없지만
    /// `isWhitespace`가 **거짓**이라 조판 문자열을 소비하는 계약을 조용히 깬다:
    /// `HwpAccessibilityContent.accessibilityLabel`의 "공백만 남으면 버린다"
    /// 판정을 통과해 읽을 것이 없는 VoiceOver 정지점을 만들고, 복사 문자열에는
    /// 어떤 다듬기에도 걸리지 않는 보이지 않는 문자가 남는다 (평문·RTF는 U+FFFC만
    /// 지운다 — `HwpSelectionGeometry.strippingControlMarkers`). 빈칸은 U+000D와
    /// 같은 공백 부류라 접기 전 계약이 그대로 유지된다. 잉크는 어느 폰트에서도
    /// 없고 (실측: HY울릉도M·함초롬바탕·Apple SD Gothic Neo 모두 마지막 줄 잉크
    /// 폭 0) 진행 폭도 화면에 드러나지 않는다 — 선택 상자·하이라이트·캐럿이
    /// 모두 `CTLineGetTrailingWhitespaceWidth`를 빼거나 그것으로 클램프해서
    /// 접기 전과 자릿수까지 같은 값을 낸다.
    ///
    /// 다만 **장식은 후행 공백을 포함한 run 폭에 그려진다** — 그 구멍은
    /// `finishEmptyLastLineAnchor`가 앵커 run의 속성을 허용
    /// 목록으로 깎아 막는다.
    func emittedText(
        of hwpChar: CoreHwp.HwpChar,
        pendingHighSurrogate: inout UInt16?,
        followsLineBreak: inout Bool,
        emittedAnchor: inout Bool
    ) -> String {
        var text = string(from: hwpChar, pendingHighSurrogate: &pendingHighSurrogate)
        if text.isEmpty, hwpChar.type == .char, hwpChar.value == 13, followsLineBreak {
            text = " "
            emittedAnchor = true
        }
        if !text.isEmpty {
            followsLineBreak = text.unicodeScalars.last == "\u{000A}"
        }
        return text
    }
}

/// 그대로 디코드하면 안 되는 제어 문자 변환.
extension HwpTextRunBuilder {
    /// WCHAR를 그대로 디코드하면 안 되는 제어 문자의 표시 대체 텍스트.
    ///
    /// 묶음 빈칸(30)·고정폭 빈칸(31)은 U+001E/U+001F로 디코드되어 CoreText가
    /// 폭 0으로 그린다 — 빈칸이 사라지고 줄바꿈이 달라진다. 두 포맷 공통
    /// 경로다 (바이너리 `HwpParaText`의 default 분기와 HWPX의 nbSpace·fwSpace가
    /// 같은 값을 낸다).
    ///
    /// 고정폭 빈칸도 U+00A0이다 — 양쪽 정렬에서 늘어나지 않는 빈칸이라 U+0020이 아니고,
    /// 폭은 문자의 글리프 폭이 아니라 빈칸 폭 패스가 준다(묶음 빈칸의 절반 — chunk 표식
    /// `HwpAttributedStringKey.fixedWidthSpace`로 가른다, #249). U+2007처럼 다른 문자로
    /// 가르지 않는 이유는 그 글리프가 없는 글꼴이 많아 CoreText가 다른 글꼴로 대체하면
    /// 진행 폭을 알 수 없기 때문이다. 대가로 U+00A0은 줄 나눔 기회가 아니어서, 두 빈칸으로만
    /// 이어진 긴 한글 음절열을 한글보다 한 음절 먼저 나눈다 (#262).
    ///
    /// 하이픈(24, HWPX `<hp:hyphen/>`)은 아무것도 그리지 않는다 — 실측
    /// (한글.app 12.30, 하이픈 유무 대조 문서): 줄 중간 글리프 없음·줄바꿈
    /// 기회 없음·줄 끝 하이픈 없음·글자 수 미집계. U+00AD로 옮기면 실물에
    /// 없는 줄바꿈 기회가 생기고, 그대로 두면 표시·복사 문자열에 U+0018이
    /// 남는다.
    ///
    /// 문단 끝(13)도 마찬가지로 떨군다 (#137). 모든 문단의 WCHAR 스트림이
    /// 13으로 끝나므로 (바이너리 `HwpParaText`의 `case 0, 1, 13`, HWPX
    /// `HwpxParagraphMapper`의 문단 끝 합성) 그대로 두면 폐해가 셋이다.
    ///
    /// 1. U+000D에 잉크가 있는 폰트에서 문단 끝마다 조판 부호가 그려진다 —
    ///    실측 2026-09-04: 한컴오피스 12.30 번들 187개 페이스 중 25개(전부 HY
    ///    계열)가 U+000D를 `¬` 모양으로 그리고, noori 3쪽 비교표 셀의 라틴
    ///    슬롯인 HY울릉도M이 그중 하나다.
    /// 2. 줄 높이가 부푼다. U+000D는 `HwpScript.detect`의 default로 `.english`가
    ///    되어 **라틴 슬롯 폰트**로 조판되는데, 그 폰트가 본문 글꼴과 다르면
    ///    CTLine ascent를 자기 기준으로 끌어올린다 (실측 13pt: "보도일시"를
    ///    휴먼명조로 조판하면 ascent 11.172인데 U+000D를 함초롬바탕으로 붙이면
    ///    13.910). 표 셀은 세로 가운데 정렬이라 글이 위로 밀렸다.
    /// 3. 표시·복사·낭독 문자열에 U+000D가 실린다 (`HwpSelectionGeometry`의
    ///    평문·RTF와 `HwpAccessibilityContent`의 라벨은 U+FFFC만 지운다).
    ///
    /// 조판 폭에는 기여하지 않으므로 (CoreText가 문단 종결자 run의 진행 폭을
    /// 0으로 만든다 — 실측: `"구 분"`과 `"구 분\r"`의
    /// `CTLineGetTypographicBounds`가 같다) 떨궈도 줄 폭·줄바꿈은 그대로다.
    /// 예외는 한 줄 끝(10) 바로 뒤에 오는 문단 끝뿐이라 `build`가 그 자리에만
    /// 빈 줄 앵커(빈칸)를 넣는다 — `emittedText` 참조.
    ///
    /// **한 줄 끝(10)은 남긴다** — 의도된 줄 나눔이라 U+000A로 조판되어야 한다.
    /// 다만 그 글자도 라틴 슬롯 폰트로 조판되면 HY 계열에서 잉크가 보이므로,
    /// 글리프를 그리지 않는 표식 run으로 낸다 (#146, `appendLineBreak`).
    static func controlText(_ unit: UInt16) -> String? {
        switch unit {
        case 13, 24:
            ""
        case 30, 31:
            "\u{00A0}"
        default:
            nil
        }
    }
}
