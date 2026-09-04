@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpTextRunBuilderTests: XCTestCase {
        static func textChars(_ text: String) -> [CoreHwp.HwpChar] {
            text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
        }

        func testEmptyParagraphReturnsEmptyAttributedString() throws {
            let paragraph = paragraph(text: "", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.length) == 0
        }

        func testBuildCapsOutputToMaxCharacters() throws {
            let paragraph = paragraph(text: String(repeating: "가", count: 5000), runs: [(0, 0)])
            let textBuilder = builder(shapes: [0: try charShape()])

            let full = textBuilder.build(paragraph: paragraph)
            let capped = textBuilder.build(paragraph: paragraph, maxCharacters: 100)

            expect(full.string.count) == 5000
            expect(capped.string.count) == 100
        }

        func testControlSpacesBecomeNonBreakingSpaces() throws {
            // 묶음 빈칸(30)·고정폭 빈칸(31)을 그대로 디코드하면 U+001E/U+001F가
            // 되어 CoreText가 폭 0으로 그린다 (실측: "가나"와 "가\u{1E}나"의
            // 타이포그래픽 폭이 같다) — 빈칸이 사라지고 줄바꿈이 달라진다.
            let paragraph = paragraph(text: "가\u{1E}나\u{1F}다", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "가\u{A0}나\u{A0}다"
        }

        func testHyphenControlRendersAsNothing() throws {
            // 하이픈(24)을 그대로 디코드하면 U+0018이 표시·복사 문자열에
            // 남는다. 실측(한글.app 12.30, `<hp:hyphen/>` 유무 대조 문서):
            // 줄 중간 글리프 없음·줄바꿈 기회 없음·줄 끝 하이픈 없음 —
            // 실물은 아무것도 그리지 않으므로 표시 문자열에서 떨군다.
            let paragraph = paragraph(text: "가\u{18}나", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "가나"
        }

        func testParagraphEndControlRendersAsNothing() throws {
            // 모든 문단의 WCHAR 스트림이 문단 끝(13)으로 끝난다. 그대로 두면
            // 표시·복사 문자열에 U+000D가 남고, 라틴 슬롯 폰트가 U+000D에 잉크를
            // 가진 HY 계열이면 문단 끝마다 '¬' 조판 부호가 그려진다 (#137).
            let paragraph = paragraph(text: "가나\u{0D}", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "가나"
        }

        func testLineBreakControlSurvivesParagraphEndFolding() throws {
            // 한 줄 끝(10)은 의도된 줄 나눔이라 U+000A로 조판되어야 한다 —
            // 문단 끝(13)을 접으면서 함께 떨구면 줄 나눔이 사라진다.
            let paragraph = paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "가\u{0A}나"
        }

        func testParagraphEndingWithLineBreakKeepsTheEmptyLastLine() throws {
            // 한 줄 끝(10)으로 끝난 문단은 한글이 라인 캐시에 마지막 빈 줄을
            // 배정한다 (실측: legacy-common-control-property Section9의 407 WCHAR
            // 문단이 세그먼트 10개, 마지막 textpos가 그 13의 자리다). CoreText는
            // 하드 개행 뒤에 내용이 있어야 그 줄을 만들므로 문단 끝을 그냥 접으면
            // 줄이 하나 사라진다 — 잉크 없는 빈칸을 앵커로 남긴다.
            let paragraph = paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "가\u{0A} "
            // 앵커는 **공백**이어야 한다 — 낭독 라벨의 "공백만 남으면 버린다"
            // 판정(`HwpAccessibilityContent.accessibilityLabel`)이 `isWhitespace`를
            // 보므로, U+200B 같은 비공백 앵커는 읽을 것이 없는 정지점을 만든다.
            expect(result.string.last?.isWhitespace) == true

            let frame = HwpParagraphLayout().layout(
                attributedString: result, paraShape: CoreHwp.HwpParaShape(), columnWidth: 300
            )
            let folded = builder(shapes: [0: try charShape()])
                .build(paragraph: self.paragraph(text: "가\u{0A}", runs: [(0, 0)]))
            let foldedFrame = HwpParagraphLayout().layout(
                attributedString: folded, paraShape: CoreHwp.HwpParaShape(), columnWidth: 300
            )
            expect(frame.lines.count) == 2
            expect(foldedFrame.lines.count) == 1
        }

        func testParagraphOfOnlyTheEndControlProducesEmptyString() throws {
            // 빈 문단의 WCHAR 스트림은 13 하나다 (HWPX는 `HwpxParagraphMapper`가
            // 항상 붙이고, 바이너리도 PARA_TEXT를 가진 빈 문단이면 같다).
            // 접고 나면 문자열이 비므로 `paraText`가 없는 빈 문단과 같은 상태가
            // 된다 — 두 포맷의 빈 문단이 같은 조판 입력으로 모인다.
            let paragraph = paragraph(text: "\u{0D}", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.length) == 0
        }

        func testControlSpacesKeepFixedWidthWhenOrdinarySpacesFollowTheFont() {
            // '글꼴에 어울리는 빈칸'·워드 호환 문서에서는 보통 빈칸이 폰트 고유
            // 폭으로 돌아간다 — 그때 고정폭 빈칸까지 글꼴을 따르면 이름과
            // 모순이라, 제어 빈칸만 게이트 밖에서 0.5em을 유지해야 한다.
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributed = NSMutableAttributedString(
                string: "가 나\u{A0}다",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            HwpTextRunBuilder.applyFixedSpaceWidth(
                to: attributed, includesOrdinarySpace: false
            )

            func advance(at location: Int) -> Double {
                let piece = attributed.attributedSubstring(
                    from: NSRange(location: location, length: 1)
                )
                return CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(piece), nil, nil, nil
                )
            }

            expect(advance(at: 3)).to(beCloseTo(6.0, within: 0.01))
            expect(advance(at: 1)).to(beLessThan(advance(at: 3)))
        }

        func testControlSpacesReceiveTheFixedSpaceWidth() {
            // U+00A0으로 옮긴 30/31도 일반 공백과 같은 0.5em 보정을 받아야
            // 한다 — 빠지면 폰트 고유 advance에 머물러 그 문단만 좁게 조판된다.
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributed = NSMutableAttributedString(
                string: "가 나\u{A0}다",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            HwpTextRunBuilder.applyFixedSpaceWidth(
                to: attributed, includesOrdinarySpace: true
            )

            func advance(at location: Int) -> Double {
                let piece = attributed.attributedSubstring(
                    from: NSRange(location: location, length: 1)
                )
                return CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(piece), nil, nil, nil
                )
            }

            expect(advance(at: 3)) == advance(at: 1)
            expect(advance(at: 3)).to(beCloseTo(6.0, within: 0.01))
        }

        func testSingleShapeParagraphProducesOneFontRange() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            let ranges = fontRanges(in: result)
            expect(result.string) == "hello"
            expect(ranges.count) == 1
            expect(ranges.first?.range) == NSRange(location: 0, length: 5)
            expect(ranges.first?.font).notTo(beNil())
        }

        func testMixedKoreanAndEnglishChunksOnScriptSwitch() throws {
            let paragraph = paragraph(text: "안녕hello", runs: [(0, 0)])
            let shape = try charShape(faceScaleX: [100, 110, 100, 100, 100, 100, 100])
            let result = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
            let rangeCount = fontRanges(in: result).count

            expect(rangeCount) >= 2
        }

        /// ZWJ·결합 마크는 직전 스크립트를 상속해 폰트 run이 갈리지 않는다 —
        /// run 경계가 생기면 CoreText가 결합 글리프(이모지 ZWJ 시퀀스)를 못 만든다.
        func testJoinerAndCombiningMarkInheritSurroundingScript() throws {
            let joined = paragraph(text: "👨\u{200D}👩", runs: [(0, 0)])
            let symbolScaled = try charShape(faceScaleX: [100, 100, 100, 100, 100, 110, 100])
            let joinedResult = builder(shapes: [0: symbolScaled]).build(paragraph: joined)
            let joinedRangeCount = fontRanges(in: joinedResult).count
            expect(joinedRangeCount) == 1

            let marked = paragraph(text: "가\u{302E}", runs: [(0, 0)])
            let englishScaled = try charShape(faceScaleX: [100, 110, 100, 100, 100, 100, 100])
            let markedResult = builder(shapes: [0: englishScaled]).build(paragraph: marked)
            let markedRangeCount = fontRanges(in: markedResult).count
            expect(markedRangeCount) == 1
        }

        func testBoldFlagProducesBoldCTFontTrait() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b10)])
                .build(paragraph: paragraph)
            let font = fontRanges(in: result).first?.font

            expect(font).notTo(beNil())
            expect(font.map { CTFontGetSymbolicTraits($0).contains(.traitBold) }) == true
        }

        func testUnderlineFlagAddsSingleUnderlineStyle() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b100)])
                .build(paragraph: paragraph)
            // CT 밑줄 대신 렌더러 전용 키 (헤어라인 직접 드로잉)
            let value = result.attribute(
                HwpAttributedStringKey.underlineStyle, at: 0, effectiveRange: nil
            ) as? NSNumber

            expect(value?.intValue) == 1
        }

        func testInlineObjectMarkerCarriesControlIndexAndRunDelegate() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "AB", suffix: "C")
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 3000)),
            ]
            let result = builder(shapes: [:]).build(paragraph: paragraph)

            expect(result.string) == "AB\u{FFFC}C"
            let markerAttributes = result.attributes(at: 2, effectiveRange: nil)
            let controlIndex = markerAttributes[HwpAttributedStringKey.controlIndex] as? NSNumber
            expect(controlIndex?.intValue) == 0
            expect(
                markerAttributes[kCTRunDelegateAttributeName as NSAttributedString.Key]
            ).toNot(beNil())
            // 일반 문자에는 컨트롤 attribute가 없다.
            let charAttributes = result.attributes(at: 0, effectiveRange: nil)
            expect(charAttributes[HwpAttributedStringKey.controlIndex]).to(beNil())
        }

        func testNonObjectExtendedControlReservesNoWidth() {
            // 구역/단/머리말 정의 마커는 한글과 같이 폭 0 (글리프 공간 없음).
            var host = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = "AB".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 16)]
            host.paraText = paraText
            host.ctrlHeaderArray = [.header(HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: []
            ))]
            let withMarker = builder(shapes: [:]).build(paragraph: host)
            expect(withMarker.string) == "AB\u{FFFC}"
            let controlIndex = withMarker.attributes(at: 2, effectiveRange: nil)[
                HwpAttributedStringKey.controlIndex
            ] as? NSNumber
            expect(controlIndex?.intValue) == 0

            let plain = builder(shapes: [:])
                .build(paragraph: paragraph(text: "AB", runs: [(0, 0)]))
            let markerLine = HwpParagraphLayout().layout(
                attributedString: withMarker,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines.first
            let plainLine = HwpParagraphLayout().layout(
                attributedString: plain,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines.first
            expect(markerLine?.width).to(beCloseTo(plainLine?.width ?? -1, within: 0.01))
        }

        func testConsecutiveExtendedControlsCountOrdinalsInOrder() {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [
                CoreHwp.HwpChar(type: .extended, value: 2),
                CoreHwp.HwpChar(type: .extended, value: 11),
            ]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .section(CoreHwp.HwpSectionDef()),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 3000)),
            ]
            let result = builder(shapes: [:]).build(paragraph: paragraph)

            expect(result.string) == "\u{FFFC}\u{FFFC}"
            let first = result.attributes(at: 0, effectiveRange: nil)
            let second = result.attributes(at: 1, effectiveRange: nil)
            expect((first[HwpAttributedStringKey.controlIndex] as? NSNumber)?.intValue) == 0
            expect((second[HwpAttributedStringKey.controlIndex] as? NSNumber)?.intValue) == 1
            // 개체 마커는 개체 크기(50pt)를, 비개체 마커는 폭 0을 예약한다.
            let lines = HwpParagraphLayout().layout(
                attributedString: result,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines
            expect(lines.first?.width).to(beCloseTo(50, within: 0.01))
            expect(lines.first?.baseline).to(beCloseTo(30, within: 0.01))
        }

        func testHyperlinkSpansNestedFieldWithoutEarlyClosing() throws {
            // 하이퍼링크(코드 3 시작 ~ 코드 4 끝) 안에 다른 필드가 중첩되면,
            // 중첩 필드의 끝 마커(inline 4)가 바깥 링크를 조기 종료하면 안 된다 (#1).
            // a〈hlk 3〉b〈필드 3〉c〈끝 4〉d〈hlk 끝 4〉e — 링크는 b..d 전체.
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            var link = CoreHwp.HwpHyperlink()
            link.url = "http://example.com/outer"
            // 긴 `+` 체인은 타입 체커가 지수적으로 느려져 느린 머신에서 컴파일이
            // 타임아웃된다 — 명시 타입 + 단계 구성으로 추론 부담을 없앤다.
            var charArray: [CoreHwp.HwpChar] = Self.textChars("a")
            charArray.append(CoreHwp.HwpChar(type: .extended, value: 3))
            charArray += Self.textChars("b")
            charArray.append(CoreHwp.HwpChar(type: .extended, value: 3))
            charArray += Self.textChars("c")
            charArray.append(CoreHwp.HwpChar(type: .inline, value: 4))
            charArray += Self.textChars("d")
            charArray.append(CoreHwp.HwpChar(type: .inline, value: 4))
            charArray += Self.textChars("e")
            paraText.charArray = charArray
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .hyperLink(link),
                .section(CoreHwp.HwpSectionDef()),
            ]
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = [0]
            paraCharShape.shapeId = [0]
            paragraph.paraCharShape = paraCharShape

            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)
            let string = result.string as NSString
            func hyperlink(at substring: String) -> String? {
                result.attribute(
                    HwpAttributedStringKey.hyperlink,
                    at: string.range(of: substring).location, effectiveRange: nil
                ) as? String
            }

            // "d"는 중첩 필드 끝 뒤 — 조기 종료됐다면 링크가 없다 (회귀 지점).
            expect(hyperlink(at: "d")) == "http://example.com/outer"
            expect(hyperlink(at: "b")) == "http://example.com/outer"
            expect(hyperlink(at: "a")).to(beNil())
            expect(hyperlink(at: "e")).to(beNil())
        }

        func testMemoAnchorRangeSpansNestedField() {
            // memo(코드 3) 안에 하이퍼링크 필드가 중첩: 중첩 종결자(inline 4)가
            // 바깥 memo 앵커를 닫으면 안 된다 (#2). 컨트롤은 스트림에서 8 WCHAR —
            // memo 시작 후 위치 8, 최종 종결자 위치 27이 앵커 범위다.
            var link = CoreHwp.HwpHyperlink()
            link.url = "http://example.com"
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            var charArray: [CoreHwp.HwpChar] = [CoreHwp.HwpChar(type: .extended, value: 3)]
            charArray += Self.textChars("a")
            charArray.append(CoreHwp.HwpChar(type: .extended, value: 3))
            charArray += Self.textChars("b")
            charArray.append(CoreHwp.HwpChar(type: .inline, value: 4))
            charArray += Self.textChars("c")
            charArray.append(CoreHwp.HwpChar(type: .inline, value: 4))
            paraText.charArray = charArray
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .memo(CoreHwp.HwpFieldControl(ctrlId: .memo)),
                .hyperLink(link),
            ]

            let ranges = HwpTextRunBuilder.memoAnchorRanges(in: paragraph)

            expect(ranges) == [UInt32(8) ..< UInt32(27)]
        }

        func testBuildClampsNegativeMaxCharactersToEmpty() throws {
            // 음수 상한은 prefix가 트랩하므로 0으로 클램프해 빈 결과를 낸다 (R45 #3).
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(
                paragraph: paragraph, maxCharacters: -5
            )
            expect(result.length) == 0
        }

        func testBuildDoesNotSplitSurrogatePairAtMaxCharacters() throws {
            // "ab😀"의 😀는 UTF-16 2유닛(high+low). 상한이 그 사이(3)를 자르면 lead
            // 서로게이트만 남아 예전엔 U+FFFD로 손상됐다 — 이제 온전한 "ab"만 남긴다.
            // 상한이 이모지를 넘으면(4) 온전히 유지한다 (R46 #1).
            let paragraph = paragraph(text: "ab😀", runs: [(0, 0)])
            let runBuilder = builder(shapes: [0: try charShape()])

            let split = runBuilder.build(paragraph: paragraph, maxCharacters: 3)
            expect(split.string) == "ab"
            expect(split.string.unicodeScalars.contains("\u{FFFD}")) == false

            let whole = runBuilder.build(paragraph: paragraph, maxCharacters: 4)
            expect(whole.string) == "ab😀"
        }

        // MARK: 글자 모양 속성 캐시 (HwpTextAttributeCache)

        func testAttributeCacheProducesIdenticalAttributedString() throws {
            // 순수 성능 캐시 — 결과가 1비트도 달라지면 안 된다. 장평·볼드·이탤릭·
            // 장식이 붙은 모양과 스크립트가 섞인 문단으로 파생 경로를 모두 태운다.
            let shapes = try decoratedShapes()
            let paragraph = paragraph(text: "가나daま?", runs: [(0, 0), (2, 1), (4, 2)])
            let cache = HwpTextAttributeCache()

            let cached = builder(shapes: shapes, cache: cache).build(paragraph: paragraph)
            let uncached = builder(shapes: shapes, cache: nil).build(paragraph: paragraph)

            expect(cached.isEqual(to: uncached)) == true
            // 2회차도 (전부 캐시 히트) 같아야 한다.
            let again = builder(shapes: shapes, cache: cache).build(paragraph: paragraph)
            expect(again.isEqual(to: uncached)) == true
        }

        func testAttributeCacheReusesEntriesAcrossBuilders() throws {
            // 같은 캐시를 공유하는 빌더끼리 (본문/표 셀/각주) 재계산이 사라진다.
            let shapes = [UInt32(0): try charShape()]
            let paragraph = paragraph(text: "가나", runs: [(0, 0)])
            let cache = HwpTextAttributeCache()

            _ = builder(shapes: shapes, cache: cache).build(paragraph: paragraph)
            expect(cache.missCount) == 1
            expect(cache.hitCount) == 0

            _ = builder(shapes: shapes, cache: cache).build(paragraph: paragraph)
            expect(cache.missCount) == 1
            expect(cache.hitCount) == 1
        }

        func testAttributeCacheKeysOnScriptAsWellAsShape() throws {
            // 같은 글자 모양이라도 스크립트마다 face/크기 슬롯이 다르다 — 키에
            // script가 빠지면 한글 run이 라틴 폰트로 그려진다.
            let shapes = [UInt32(0): try charShape()]
            let cache = HwpTextAttributeCache()

            _ = builder(shapes: shapes, cache: cache)
                .build(paragraph: paragraph(text: "가a", runs: [(0, 0)]))

            expect(cache.missCount) == 2
            expect(cache.hitCount) == 0
        }

        func testAttributeCacheIsNotPollutedByPerRunTrackChangeMark() throws {
            // 변경추적 표시는 반환된 사전의 사본에만 붙는다 — 캐시 항목을 제자리에서
            // 바꾸면 같은 글자 모양의 비-추적 run까지 빨갛게 물든다.
            var tracked = paragraph(text: "가나다라", runs: [(0, 0)])
            tracked.paraRangeTagArray = [try rangeTag(start: 0, end: 2, kind: 16)]
            let shapes = [UInt32(0): try charShape()]

            let result = builder(shapes: shapes, cache: HwpTextAttributeCache())
                .build(paragraph: tracked)

            let colorKey = kCTForegroundColorAttributeName as NSAttributedString.Key
            let marked = result.attributes(at: 0, effectiveRange: nil)[colorKey]
            let plain = result.attributes(at: 2, effectiveRange: nil)[colorKey]
            let expected = builder(shapes: shapes, cache: nil)
                .build(paragraph: paragraph(text: "가나다라", runs: [(0, 0)]))
                .attributes(at: 0, effectiveRange: nil)[colorKey]

            expect(CFEqual(marked as CFTypeRef, plain as CFTypeRef)) == false
            expect(CFEqual(plain as CFTypeRef, expected as CFTypeRef)) == true
        }

        func testAttributeCacheReusesTabStopsPerTabDefinition() {
            // CTTextTab은 불변이고 tabDefId만의 함수라 문서 안에서 공유한다.
            let cache = HwpTextAttributeCache()
            let paraShape = CoreHwp.HwpParaShape()
            let documentIndex = index(shapes: [:])

            let first = cache.textTabs(for: paraShape, index: documentIndex)
            let second = cache.textTabs(for: paraShape, index: documentIndex)

            expect(first.count) == documentIndex.textTabs(for: paraShape).count
            expect(second.count) == first.count
        }

        func testAttributeCacheFoldsUnresolvedShapeIdsIntoOneEntry() {
            // index에 없는 id는 문단과 무관한 상수 폴백을 쓰므로 결과 사전이 전부
            // 같다 — 원본 id로 키를 잡으면 조작 문서가 문자마다 다른 id를 흘려
            // 내용이 같은 항목을 문서 수명 내내 쌓는다 (R41 P1 리뷰).
            let cache = HwpTextAttributeCache()
            let distinctUnresolved = (0 ..< 64).map { (UInt32($0), UInt32($0) &* 7 &+ 1) }
            let paragraph = paragraph(
                text: String(repeating: "가", count: 64), runs: distinctUnresolved
            )

            _ = builder(shapes: [:], cache: cache).build(paragraph: paragraph)

            expect(cache.entryCount) == 1
            expect(cache.missCount) == 1
            expect(cache.hitCount) == 63
        }

        func testAttributeCacheStopsInsertingBeyondEntryLimit() throws {
            // 상한 초과는 축출이 아니라 삽입 중단 — 미스가 create 폴백이라
            // 결과는 그대로여야 한다 (느려질 뿐).
            let shapes = try decoratedShapes()
            let paragraph = paragraph(text: "가나다", runs: [(0, 0), (1, 1), (2, 2)])
            let cache = HwpTextAttributeCache()
            cache.maximumEntries = 2

            let capped = builder(shapes: shapes, cache: cache).build(paragraph: paragraph)
            let uncached = builder(shapes: shapes, cache: nil).build(paragraph: paragraph)

            expect(cache.entryCount) == 2
            expect(capped.isEqual(to: uncached)) == true
        }
    }

    private extension HwpTextRunBuilderTests {
        func builder(shapes: [UInt32: CoreHwp.HwpCharShape]) -> HwpTextRunBuilder {
            HwpTextRunBuilder(index: index(shapes: shapes), fontResolver: .testDeterministic)
        }

        /// 캐시를 공유하는 빌더 — 캐시가 문서 단위 소유라는 계약대로, 같은 내용의
        /// `index`를 쓰는 빌더끼리만 하나를 나눠 쓴다.
        func builder(
            shapes: [UInt32: CoreHwp.HwpCharShape],
            cache: HwpTextAttributeCache?
        ) -> HwpTextRunBuilder {
            HwpTextRunBuilder(
                index: index(shapes: shapes),
                fontResolver: .testDeterministic,
                attributeCache: cache
            )
        }

        /// 장평·볼드·이탤릭·밑줄·그림자가 붙은 모양 3종 (파생 CTFont 경로 전수)
        func decoratedShapes() throws -> [UInt32: CoreHwp.HwpCharShape] {
            [
                0: try charShape(),
                // 표 33 property: bit 0 이탤릭 / bit 1 진하게 / bits 2-4 밑줄 종류
                1: try charShape(property: 0b111, faceScaleX: Array(repeating: 90, count: 7)),
                2: try charShape(property: 0b10, faceScaleX: Array(repeating: 120, count: 7)),
            ]
        }

        /// 변경추적 range tag (상위 8비트 = 종류, 16 삽입 / 17 삭제)
        func rangeTag(
            start: UInt32,
            end: UInt32,
            kind: UInt32
        ) throws -> CoreHwp.HwpParaRangeTag {
            var data = Data()
            append(start, to: &data)
            append(end, to: &data)
            append(kind << 24, to: &data)
            return try CoreHwp.HwpParaRangeTag.load(data)
        }

        func index(shapes: [UInt32: CoreHwp.HwpCharShape]) -> HwpIndex {
            HwpIndex(
                charShapes: shapes,
                paraShapes: [:],
                borderFills: [:],
                tabDefs: [:],
                styles: [:],
                bullets: [:],
                numberings: [:],
                binData: [:],
                faceNamesKorean: [:],
                faceNamesEnglish: [:],
                faceNamesChinese: [:],
                faceNamesJapanese: [:],
                faceNamesEtc: [:],
                faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }

        func paragraph(text: String, runs: [(UInt32, UInt32)]) -> CoreHwp.HwpParagraph {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText

            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = runs.map(\.0)
            paraCharShape.shapeId = runs.map(\.1)
            paragraph.paraCharShape = paraCharShape
            return paragraph
        }

        func charShape(
            property: UInt32 = 0,
            faceScaleX: [UInt8] = [100, 100, 100, 100, 100, 100, 100]
        ) throws -> CoreHwp.HwpCharShape {
            var data = Data()
            append(UInt16(0), count: 7, to: &data)
            data.append(contentsOf: faceScaleX)
            data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0].map { UInt8(bitPattern: Int8($0)) })
            data.append(contentsOf: [100, 100, 100, 100, 100, 100, 100])
            data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0].map { UInt8(bitPattern: Int8($0)) })
            append(Int32(1200), to: &data)
            append(property, to: &data)
            data.append(UInt8(bitPattern: Int8(0)))
            data.append(UInt8(bitPattern: Int8(0)))
            append(UInt32(0), count: 4, to: &data)
            return try CoreHwp.HwpCharShape.load(data, CoreHwp.HwpVersion(5, 0, 1, 0))
        }

        func fontRanges(in string: NSAttributedString) -> [(range: NSRange, font: CTFont?)] {
            var ranges: [(NSRange, CTFont?)] = []
            string.enumerateAttribute(
                kCTFontAttributeName as NSAttributedString.Key,
                in: NSRange(location: 0, length: string.length)
            ) { value, range, _ in
                // swiftlint:disable:next force_cast
                ranges.append((range, value.map { $0 as! CTFont }))
            }
            return ranges
        }

        func append(_ value: some FixedWidthInteger, count: Int, to data: inout Data) {
            for _ in 0 ..< count {
                append(value, to: &data)
            }
        }

        func append(_ value: some FixedWidthInteger, to data: inout Data) {
            var littleEndian = value.littleEndian
            data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
        }
    }
#endif
