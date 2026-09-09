@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 제어 문자 조판 계약 — `HwpTextRunBuilderMarks.swift`·
    /// `HwpTextRunBuilderLineBreak.swift`의 짝이다. 묶음/고정폭 빈칸(30·31)·
    /// 하이픈(24)·문단 끝(13)과 그 빈 줄 앵커, 앵커가 사용자 입력 빈칸과 구별되는지,
    /// 그리고 한 줄 끝(10)의 글리프 없는 표식 run(#146)을 잠근다.
    ///
    /// 헬퍼(`paragraph`·`charShape`·`builder`)는 `HwpTextRunBuilderTests`의
    /// 확장에 있으므로 같은 타입의 확장으로 둔다 — 픽스처를 복제하지 않는다.
    extension HwpTextRunBuilderTests {
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

        func testLineBreakRunIsMarkedAndCarriesNoDecoration() throws {
            // 한 줄 끝(10)은 U+000A 한 글자로 남되 글리프를 그리지 않는 표식 run이다
            // (#146) — 한컴 번들의 HY 계열 폰트는 그 코드에 잉크 있는 글리프를 가져,
            // 라틴 슬롯 폰트로 조판되던 종전에는 Shift+Enter 자리마다 조판 부호가
            // 보였다. 장식은 run 폭에 그려지므로 (`HwpPageLayerDecorations.runBounds`)
            // 함께 떼어 낸다 — 진행 폭이 1em인 폰트에서 줄 끝에 밑줄 토막이 남는다.
            let paragraph = paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)])
            let underlined = try charShape(property: 1 << 2)
            let result = builder(shapes: [0: underlined]).build(paragraph: paragraph)

            expect(result.string) == "가\u{0A}나"
            let lineBreak = result.attributes(at: 1, effectiveRange: nil)
            expect(lineBreak[HwpAttributedStringKey.lineBreak]).notTo(beNil())
            // 줄 높이를 정하는 글꼴·기준 크기는 남고 장식 키는 하나도 없다.
            expect(lineBreak[kCTFontAttributeName as NSAttributedString.Key]).notTo(beNil())
            expect(lineBreak[HwpAttributedStringKey.baseFontSize]).notTo(beNil())
            expect(lineBreak[HwpAttributedStringKey.underlineStyle]).to(beNil())
            expect(lineBreak[HwpAttributedStringKey.underlineColor]).to(beNil())
            // 표식은 그 한 글자에만 붙고 양옆 글자의 장식은 그대로다.
            for location in [0, 2] {
                let neighbor = result.attributes(at: location, effectiveRange: nil)
                expect(neighbor[HwpAttributedStringKey.lineBreak]).to(beNil())
                expect(neighbor[HwpAttributedStringKey.underlineStyle]).notTo(beNil())
            }
        }

        func testLoneSurrogateBeforeLineBreakStaysOutsideTheMarkedRun() throws {
            // 짝 없는 상위 서로게이트 뒤에 한 줄 끝이 오면 `string(from:)`이 잔여
            // U+FFFD와 U+000A를 한 텍스트로 낸다 — 앞부분은 일반 chunk로 가고 표식은
            // 한 줄 끝 한 글자에만 붙어야 한다. Swift 문자열에는 홀 서로게이트를
            // 넣을 수 없어 WCHAR 배열을 직접 만든다.
            var paragraph = paragraph(text: "", runs: [(0, 0)])
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [0xD83D, 0x0A, 0xAC00, 0x0D].map {
                CoreHwp.HwpChar(type: .char, value: $0)
            }
            paragraph.paraText = paraText
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.string) == "\u{FFFD}\u{0A}가"
            expect(result.attribute(HwpAttributedStringKey.lineBreak, at: 0, effectiveRange: nil))
                .to(beNil())
            expect(result.attribute(HwpAttributedStringKey.lineBreak, at: 1, effectiveRange: nil))
                .notTo(beNil())
            expect(result.attribute(HwpAttributedStringKey.lineBreak, at: 2, effectiveRange: nil))
                .to(beNil())
        }

        func testLineBreakInheritsThePrecedingRunScriptSlot() throws {
            // 한 줄 끝의 글꼴은 `HwpScript.detect` 기본값(영문 슬롯)이 아니라 **직전
            // run의 스크립트 슬롯**이다 — 본문과 다른 폰트가 줄에 섞이면 CTLine
            // ascent가 그 폰트 기준으로 부푼다 (#137이 문단 끝 코드에서 겪은 축).
            // 영문 슬롯 장평만 80%로 줘 두 슬롯의 CTFont가 갈리게 한다.
            let shape = try charShape(faceScaleX: [100, 80, 100, 100, 100, 100, 100])
            let afterKorean = builder(shapes: [0: shape])
                .build(paragraph: paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)]))
            let afterLatin = builder(shapes: [0: shape])
                .build(paragraph: paragraph(text: "a\u{0A}나\u{0D}", runs: [(0, 0)]))
            expect(self.sameFont(afterKorean, 1, afterKorean, 0)) == true
            expect(self.sameFont(afterLatin, 1, afterLatin, 0)) == true
            // 두 슬롯이 실제로 다른 글꼴이어야 위 두 단언이 뜻을 갖는다.
            expect(self.sameFont(afterKorean, 0, afterLatin, 0)) == false

            // 직전 run이 없는 문단 첫 글자는 한글 슬롯이다 — 빈 문단 앵커와 같은 선택.
            let leading = builder(shapes: [0: shape])
                .build(paragraph: paragraph(text: "\u{0A}가\u{0D}", runs: [(0, 0)]))
            expect(self.sameFont(leading, 0, leading, 1)) == true
        }

        func testLineBreakKeepsLineBreakingAndLineGeometry() throws {
            // 표식 run이 줄 나눔·줄 기하를 바꾸면 안 된다: 한 줄 끝이 든 첫 줄은 그
            // 글자를 뺀 한 줄 문단과 프레임(원점·베이스라인·폭)이 같고, 둘째 줄이 그
            // 아래에 생긴다. CoreText는 개행 글리프를 줄 폭에 넣지 않으므로 (실측:
            // HY울릉도M 15pt에서 "구 분"과 "구 분\n"의 typographic 폭이 같다) 진행
            // 폭이 1em인 폰트에서도 성립한다.
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            let broken = builder(shapes: shapes)
                .build(paragraph: paragraph(text: "구 분\u{0A}다음 줄\u{0D}", runs: [(0, 0)]))
            let single = builder(shapes: shapes)
                .build(paragraph: paragraph(text: "구 분\u{0D}", runs: [(0, 0)]))
            let layout = HwpParagraphLayout()
            let brokenFrame = layout.layout(
                attributedString: broken, paraShape: CoreHwp.HwpParaShape(), columnWidth: 300
            )
            let singleFrame = layout.layout(
                attributedString: single, paraShape: CoreHwp.HwpParaShape(), columnWidth: 300
            )
            expect(brokenFrame.lines.count) == 2
            expect(singleFrame.lines.count) == 1
            let first = brokenFrame.lines[0]
            let only = singleFrame.lines[0]
            expect(first.origin.x) == only.origin.x
            expect(first.origin.y) == only.origin.y
            expect(first.baseline) == only.baseline
            expect(first.width) == only.width
            expect(first.attributedRange.location) == 0
            expect(first.attributedRange.length) == 4
            expect(brokenFrame.lines[1].origin.y > first.origin.y) == true
        }

        func testLineBreakDoesNotShiftRightAlignedLines() throws {
            // 오른쪽 정렬에서 개행 글리프의 진행 폭이 줄 위치에 끼면 첫 줄이 왼쪽으로
            // 밀린다 — 한 줄 끝이 든 첫 줄의 원점 x는 그 글자를 뺀 한 줄 문단과 같다.
            // 문단 모양 속성1 bits 2-4 = 정렬 (2 오른쪽).
            let rightAligned = CoreHwp.HwpParaShape(
                property1: 2 << 2, marginLeft: 0, lineSpacing: 160, tabDefId: 0, lineSpacing2: 160
            )
            let textBuilder = HwpTextRunBuilder(
                index: HwpIndex(
                    charShapes: [0: try charShape()],
                    paraShapes: [0: rightAligned],
                    borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                    binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:],
                    faceNamesChinese: [:], faceNamesJapanese: [:], faceNamesEtc: [:],
                    faceNamesSymbol: [:], faceNamesUser: [:]
                ),
                fontResolver: .testDeterministic
            )
            let broken = textBuilder
                .build(paragraph: paragraph(text: "구 분\u{0A}다음 줄\u{0D}", runs: [(0, 0)]))
            let single = textBuilder
                .build(paragraph: paragraph(text: "구 분\u{0D}", runs: [(0, 0)]))
            let layout = HwpParagraphLayout()
            let brokenFrame = layout.layout(
                attributedString: broken, paraShape: rightAligned, columnWidth: 300
            )
            let singleFrame = layout.layout(
                attributedString: single, paraShape: rightAligned, columnWidth: 300
            )
            expect(brokenFrame.lines.count) == 2
            expect(singleFrame.lines.count) == 1
            let first = brokenFrame.lines[0]
            let only = singleFrame.lines[0]
            // 오른쪽 정렬이 실제로 걸렸는지 — 원점이 단 왼쪽이 아니어야 한다.
            expect(only.origin.x).to(beGreaterThan(100))
            expect(first.origin.x) == only.origin.x
        }

        /// 두 자리의 CTFont가 같은가 — `CFEqual`은 매트릭스(장평)까지 본다. CF 타입은
        /// `as?`가 "항상 성공" 에러라 루트 AGENTS.md의 `CFGetTypeID` + `unsafeBitCast`
        /// 패턴으로 꺼낸다 (`HwpNumberingHeadingRenderTests.font(at:in:)`와 같다).
        func sameFont(
            _ lhs: NSAttributedString, _ lhsLocation: Int,
            _ rhs: NSAttributedString, _ rhsLocation: Int
        ) -> Bool {
            guard let lhsFont = runFont(at: lhsLocation, in: lhs),
                  let rhsFont = runFont(at: rhsLocation, in: rhs)
            else { return false }
            return CFEqual(lhsFont, rhsFont)
        }

        func runFont(at location: Int, in attributed: NSAttributedString) -> CTFont? {
            guard let value = attributed.attribute(
                kCTFontAttributeName as NSAttributedString.Key, at: location, effectiveRange: nil
            ) else { return nil }
            let reference = value as CFTypeRef
            guard CFGetTypeID(reference) == CTFontGetTypeID() else { return nil }
            return unsafeBitCast(reference, to: CTFont.self)
        }

        func testEmptyLastLineAnchorCarriesNoDecoration() throws {
            // 장식은 글리프가 아니라 run 폭에 그려지고 그 폭은 후행 공백을
            // 포함한다 (`HwpPageLayerDecorations.runBounds`). 앵커가 마지막 글자
            // 모양의 밑줄·취소선을 물려받으면 빈 줄에 장식 토막이 남는다.
            let paragraph = paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 0)])
            let underlined = try charShape(property: 1 << 2)
            let result = builder(shapes: [0: underlined]).build(paragraph: paragraph)

            let attributes = result.attributes(at: result.length - 1, effectiveRange: nil)
            expect(result.string.last) == " "
            // 높이를 정하는 글꼴은 남고, 장식 키는 하나도 남지 않는다.
            expect(attributes[kCTFontAttributeName as NSAttributedString.Key]).notTo(beNil())
            expect(attributes[HwpAttributedStringKey.underlineStyle]).to(beNil())
            expect(attributes[HwpAttributedStringKey.underlineColor]).to(beNil())
            expect(attributes[HwpAttributedStringKey.emptyLineAnchor]).notTo(beNil())
            // 앞 글자에는 그대로 있어야 한다 — 앵커만 깎였음을 확인한다.
            let body = result.attributes(at: 0, effectiveRange: nil)
            expect(body[HwpAttributedStringKey.underlineStyle]).notTo(beNil())
        }

        func testUserSpaceBeforeParagraphEndKeepsItsDecoration() throws {
            // `가 + LF + 빈칸 + CR`는 조판 문자열이 앵커 경우와 **글자까지 같다**
            // (둘 다 "가\n "). 꼬리 문자열로 앵커를 판정하면 이 진짜 빈칸의
            // 밑줄·변경 추적·메모 강조까지 함께 떨어진다 — 판정은 방출 시점의
            // 표식으로만 해야 한다.
            let paragraph = paragraph(text: "가\u{0A}\u{20}\u{0D}", runs: [(0, 0)])
            let underlined = try charShape(property: 1 << 2)
            let result = builder(shapes: [0: underlined]).build(paragraph: paragraph)

            let anchored = builder(shapes: [0: underlined])
                .build(paragraph: self.paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 0)]))
            expect(result.string) == anchored.string

            let attributes = result.attributes(at: result.length - 1, effectiveRange: nil)
            expect(attributes[HwpAttributedStringKey.underlineStyle]).notTo(beNil())
            expect(attributes[HwpAttributedStringKey.emptyLineAnchor]).to(beNil())
        }

        func testEmptyParagraphAnchorGivesOneLineHeightWithoutCache() throws {
            // 빈 문단의 조판 문자열은 빈 문단 앵커다 (#145). 라인 캐시가 없는
            // 측정 경로에서도 `layout`이 한 줄 높이를 내야 빈 줄이 살아남는다
            // (#137). HWPX의 빈 문단이 정확히 이 모양이다 (`charArray == [13]`).
            let paragraph = paragraph(text: "\u{0D}", runs: [(0, 0)])
            let built = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)
            expect(HwpTextRunBuilder.isEmptyParagraphAnchor(built)) == true

            let frame = HwpParagraphLayout().layout(
                attributedString: built, paraShape: CoreHwp.HwpParaShape(), columnWidth: 300
            )
            expect(frame.totalHeight).to(beGreaterThan(0))
            expect(frame.lines.count) == 1
        }

        func testEmptyParagraphShapesConvergeOnTheSameAnchor() throws {
            // 빈 문단의 세 모델 형태 — HWP 바이너리(PARA_TEXT 없음)·빈 배열·
            // HWPX(문단 끝 코드 13뿐, 하이픈만 있는 문단 포함) — 가 같은 앵커로
            // 모여야 두 포맷이 같게 선택·복사된다. 앵커는 글꼴·문단 스타일만
            // 갖고 장식은 없다 (빈 줄 앵커와 같은 허용 목록).
            let underlined = try charShape(property: 1 << 2)
            var withoutParaText = paragraph(text: "", runs: [(0, 0)])
            withoutParaText.paraText = nil
            let shapes = [
                withoutParaText,
                paragraph(text: "", runs: [(0, 0)]),
                paragraph(text: "\u{0D}", runs: [(0, 0)]),
                paragraph(text: "\u{18}\u{0D}", runs: [(0, 0)]),
            ]
            for shape in shapes {
                let result = builder(shapes: [0: underlined]).build(paragraph: shape)
                expect(result.string) == " "
                let attributes = result.attributes(at: 0, effectiveRange: nil)
                expect(attributes[HwpAttributedStringKey.emptyLineAnchor]).notTo(beNil())
                expect(attributes[kCTFontAttributeName as NSAttributedString.Key]).notTo(beNil())
                expect(attributes[kCTParagraphStyleAttributeName as NSAttributedString.Key])
                    .notTo(beNil())
                expect(attributes[HwpAttributedStringKey.underlineStyle]).to(beNil())
            }
        }

        func testTruncatedBuildDoesNotSynthesizeAnAnchor() throws {
            // 상한으로 잘린 결과(메모 표시 예산)는 빈 문단이 아니다 — 앵커를
            // 만들면 잘린 문단이 빈 줄 하나로 보인다.
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(
                paragraph: paragraph, maxCharacters: 0
            )
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
    }
#endif
