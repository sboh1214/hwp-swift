import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 줄 끝의 필드 끝 (#260 리뷰) — 하이퍼링크 끝은 inline 코드 4라 `controlIndex` 없는 폭 0 표식으로
    /// 나온다. 한글은 줄 끝 자간 규칙에서 그 표식을 없는 것으로 본다(링크로 끝나는 줄도 같은 평문 줄과
    /// 같다 — 한글 12.30 build 6523 실측). 실제 빌더가 만든 링크 문단으로 잰다 — Menlo 12pt(결정론
    /// resolver) 라틴 자간.
    extension HwpTextRunBuilderTests {
        private enum LinkAlignment: UInt32, CaseIterable {
            case left = 1
            case right = 2
            case center = 3
        }

        /// 필드 시작(extended 코드 3).
        private static let fieldStart = CoreHwp.HwpChar(type: .extended, value: 3)
        /// 필드 끝(inline 코드 4).
        private static let fieldEnd = CoreHwp.HwpChar(type: .inline, value: 4)

        private static var link: CoreHwp.HwpCtrlId {
            var link = CoreHwp.HwpHyperlink()
            link.url = "http://example.com"
            return .hyperLink(link)
        }

        /// `chars`·`controls`(extended 컨트롤 순서)로 만든 문단을 Menlo 12pt 라틴 자간 `spacing`%,
        /// 정렬 `alignment`로 조판한 문자열.
        private func builtParagraph(
            _ chars: [CoreHwp.HwpChar], controls: [CoreHwp.HwpCtrlId] = [], spacing: Int8,
            alignment: LinkAlignment
        ) throws -> NSAttributedString {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = chars
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = controls
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = [0]
            paraCharShape.shapeId = [0]
            paragraph.paraCharShape = paraCharShape
            let documentIndex = HwpIndex(
                charShapes: [0: try charShape(faceSpacing: [0, spacing, 0, 0, 0, 0, 0])],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: alignment.rawValue << 2, marginLeft: 0, tabDefId: 0
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            return HwpTextRunBuilder(index: documentIndex, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
        }

        /// `prefix` + 하이퍼링크(필드 시작 코드 3 ~ 끝 inline 코드 4)로 감싼 `linked` + `suffix`.
        private func linkedParagraph(
            prefix: String = "", linked: String, suffix: String = "", spacing: Int8,
            alignment: LinkAlignment
        ) throws -> NSAttributedString {
            var chars = Self.textChars(prefix)
            chars.append(Self.fieldStart)
            chars += Self.textChars(linked)
            chars.append(Self.fieldEnd)
            chars += Self.textChars(suffix)
            return try builtParagraph(
                chars, controls: [Self.link], spacing: spacing, alignment: alignment
            )
        }

        /// Menlo 12pt `a`의 전진량.
        private var menloAdvance: CGFloat {
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil)
            var character: UniChar = 0x61
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width
        }

        /// 첫 줄에 그려지는 글자(U+FFFC 표식 제외)와 그 x — 문자열 순서.
        private static func drawnLetters(
            of attributed: NSAttributedString, lineWidth: CGFloat
        ) throws -> [(letter: UniChar, x: CGFloat)] {
            let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: .zero, lineWidth: lineWidth
            ).first)
            let string = attributed.string as NSString
            let base = CTLineGetStringRange(line.line).location - line.stringRange.location
            var letters: [Int: (letter: UniChar, x: CGFloat)] = [:]
            for run in CTLineGetGlyphRuns(line.line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                for (position, stringIndex) in zip(positions, indices) {
                    let index = stringIndex - base
                    let letter = string.character(at: index)
                    guard letter != 0xFFFC else { continue }
                    let x = line.baselineOrigin.x + position.applying(CTRunGetTextMatrix(run)).x
                    letters[index] = (letter, x)
                }
            }
            return letters.keys.sorted().compactMap { letters[$0] }
        }

        func testLineEndSeesThroughAHyperlinkFieldEnd() throws {
            // 실제 링크 끝 표식은 `controlIndex`가 없다(inline 컨트롤) — 그래도 폭 0 컨트롤 표식이라 그 앞
            // 글자가 마지막 글자다. 링크 안 필드처럼 끝 표식이 둘 이어져도 둘 다 건너뛴다.
            let nested = [Self.fieldStart, Self.fieldStart] + Self.textChars("abcd")
                + [Self.fieldEnd, Self.fieldEnd]
            for spacing: Int8 in [-20, 20] {
                let single = try linkedParagraph(linked: "abcd", spacing: spacing, alignment: .left)
                let double = try builtParagraph(
                    nested, controls: [Self.link, Self.link], spacing: spacing, alignment: .left
                )
                for attributed in [single, double] {
                    let string = attributed.string as NSString
                    let markerIndex = string.length - 1
                    expect(string.character(at: markerIndex)) == 0xFFFC
                    expect(attributed.attribute(
                        HwpAttributedStringKey.controlIndex, at: markerIndex, effectiveRange: nil
                    )).to(beNil())
                    let end = HwpLetterSpacing.lineEnd(
                        in: attributed, range: NSRange(location: 0, length: string.length)
                    )
                    expect(end.spacing)
                        .to(beCloseTo(menloAdvance * CGFloat(spacing) / 100, within: 1e-9))
                    expect(end.followedByControl) == true
                }
            }
        }

        func testLinkedLinesMatchPlainTextGlyphForGlyph() throws {
            // 링크로 끝나는 줄은 왼쪽·오른쪽·가운데 정렬 모두 같은 평문 줄과 글자 자리가 같다 (한글: 링크 끝
            // 유무와 같은 자리). 링크가 줄 일부만 감싸도, 링크 끝 뒤에 빈칸이 와도, 끝 표식이 겹쳐도 같다.
            let nested = [Self.fieldStart] + Self.textChars("ab") + [Self.fieldStart]
                + Self.textChars("cd") + [Self.fieldEnd, Self.fieldEnd]
            for alignment in LinkAlignment.allCases {
                for spacing: Int8 in [-20, 20] {
                    let label = "\(alignment) \(spacing)%"
                    let plain = try Self.drawnLetters(
                        of: builtParagraph(
                            Self.textChars("abcd"), spacing: spacing, alignment: alignment
                        ),
                        lineWidth: 200
                    )
                    let plainSpace = try Self.drawnLetters(
                        of: builtParagraph(
                            Self.textChars("abcd "), spacing: spacing, alignment: alignment
                        ),
                        lineWidth: 200
                    )
                    // 이름이 빈칸으로 끝나는 사례는 빈칸까지 있는 평문과 댄다.
                    let cases: [(String, NSAttributedString)] = [
                        ("|abcd", try linkedParagraph(
                            linked: "abcd", spacing: spacing, alignment: alignment
                        )),
                        ("ab|cd", try linkedParagraph(
                            prefix: "ab", linked: "cd", spacing: spacing, alignment: alignment
                        )),
                        ("nested", try builtParagraph(
                            nested, controls: [Self.link, Self.link], spacing: spacing,
                            alignment: alignment
                        )),
                        ("|abcd| ", try linkedParagraph(
                            linked: "abcd", suffix: " ", spacing: spacing, alignment: alignment
                        )),
                    ]
                    for (name, attributed) in cases {
                        let expected = name.hasSuffix(" ") ? plainSpace : plain
                        let letters = try Self.drawnLetters(of: attributed, lineWidth: 200)
                        expect(letters.map(\.letter)).to(
                            equal(expected.map(\.letter)), description: "\(label) \(name)"
                        )
                        for (drawn, reference) in zip(letters, expected) {
                            expect(drawn.x).to(
                                beCloseTo(reference.x, within: 0.01),
                                description: "\(label) \(name)"
                            )
                        }
                    }
                }
            }
        }

        func testNegativeSpacingLineBreakIgnoresAHyperlinkFieldEnd() throws {
            // 링크로 끝나는 줄의 음수 자간 줄 나눔도 평문과 같다 — 7단어가 자간을 넣고 재면 들어가고 빼고 재면
            // 넘치는 폭에서 6단어(한글 실측도 링크 유무와 같은 6단어). 링크 끝을 마지막 글자로 보면 자간 0으로
            // 읽어 7단어를 한 줄에 두었다. 측정(`HwpParagraphLayout`)도 렌더와 같은 줄 범위다.
            let glyph = menloAdvance * 0.8
            let seven = CGFloat(35) * glyph + 6 * 6 * 0.8
            let unspaced = seven - menloAdvance * -0.2
            let width = (seven + unspaced) / 2
            let linked = try linkedParagraph(
                linked: Array(repeating: "aaaaa", count: 7).joined(separator: " "), spacing: -20,
                alignment: .left
            )
            let lines = HwpDrawnTextLayout.lines(
                attributedString: linked, origin: .zero, lineWidth: width
            )
            let string = linked.string as NSString
            let first = try XCTUnwrap(lines.first)
            let glyphs = (0 ..< first.stringRange.length).filter {
                string.character(at: first.stringRange.location + $0) == 0x61
            }.count
            expect(glyphs) == 30
            let measured = HwpParagraphLayout().layout(
                attributedString: linked,
                paraShape: CoreHwp.HwpParaShape(property1: 1 << 2, marginLeft: 0, tabDefId: 0),
                columnWidth: width
            )
            expect(measured.lines.map(\.attributedRange)) == lines.map(\.stringRange)
        }

        func testObjectsAndLiteralReplacementCharactersAreContent() throws {
            // 판별의 두 경계: 글자처럼 취급 개체의 표식(예약 높이)과 문서 본문의 U+FFFC 글자(빌더 마커 표식 없음)는
            // 내용 글자다 — 줄 끝 자간 규칙이 그 앞 글자로 건너뛰지 않는다.
            let object = try builtParagraph(
                Self.textChars("abcd") + [CoreHwp.HwpChar(type: .extended, value: 11)],
                controls: [.genShapeObject(
                    HwpSynthetic.inlineShapeObject(width: 2000, height: 1000)
                )],
                spacing: -20, alignment: .left
            )
            let literal = try builtParagraph(
                Self.textChars("abcd") + [CoreHwp.HwpChar(type: .char, value: 0xFFFC)],
                spacing: -20, alignment: .left
            )
            for (name, attributed) in [("object", object), ("literal", literal)] {
                let string = attributed.string as NSString
                let last = string.length - 1
                expect(string.character(at: last)).to(equal(0xFFFC), description: name)
                expect(HwpLetterSpacing.isZeroWidthControlMarker(
                    0xFFFC, in: attributed, at: last
                )).to(beFalse(), description: name)
                let end = HwpLetterSpacing.lineEnd(
                    in: attributed, range: NSRange(location: 0, length: string.length)
                )
                expect(end.followedByControl).to(beFalse(), description: name)
            }
            expect(object.attribute(
                HwpAttributedStringKey.inlineObjectHeight, at: object.length - 1,
                effectiveRange: nil
            )).toNot(beNil())
        }

        func testHostAttachmentAfterSpacedTextIsContent() throws {
            // 공개 `HwpDrawnTextLayout.lines`에 호스트가 조판 문자열 뒤에 자기 delegate 첨부(폭 30, refcon 없음)를
            // 이어 붙여도 그 첨부는 내용 글자다 — 줄 끝 자간 보정은 첨부 앞 글자로 건너뛰지 않고, 오른쪽 정렬
            // 첨부가 오른쪽 끝(200pt)에 맞는다 (PR 리뷰 실측: delegate 유무로 가르면 198.56·201.44pt). refcon을 읽지
            // 않으므로 크래시도 없다.
            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateVersion1, dealloc: { _ in },
                getAscent: { _ in 10 }, getDescent: { _ in 0 }, getWidth: { _ in 30 }
            )
            let hostDelegate = try XCTUnwrap(CTRunDelegateCreate(&callbacks, nil))
            for spacing: Int8 in [-20, 20] {
                let built = try builtParagraph(
                    Self.textChars("abcd"), spacing: spacing, alignment: .right
                )
                let string = NSMutableAttributedString(attributedString: built)
                var attachment = built.attributes(at: 0, effectiveRange: nil)
                attachment[HwpAttributedStringKey.letterSpacing] = nil
                attachment[kCTKernAttributeName as NSAttributedString.Key] = nil
                attachment[kCTTrackingAttributeName as NSAttributedString.Key] = nil
                attachment[kCTRunDelegateAttributeName as NSAttributedString.Key] = hostDelegate
                string.append(NSAttributedString(string: "\u{FFFC}", attributes: attachment))
                let end = HwpLetterSpacing.lineEnd(
                    in: string, range: NSRange(location: 0, length: string.length)
                )
                expect(end.followedByControl).to(beFalse(), description: "\(spacing)%")
                let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                    attributedString: string, origin: .zero, lineWidth: 200
                ).first)
                let width = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
                expect(line.baselineOrigin.x + width)
                    .to(beCloseTo(200, within: 0.01), description: "\(spacing)%")
            }
        }

        func testBuilderMarkersAreZeroWidthExactlyWhenTheyAreControlMarkers() throws {
            // 판별의 근거인 빌더 불변식: 빌더가 낸 U+FFFC는 폭 0 컨트롤 표식으로 판정되면 CoreText 폭이 0이고,
            // 아니면(글자처럼 취급 개체) 폭이 있다. 필드 시작(extended)·끝(inline)·구역 정의(extended 비개체)·
            // 개체를 한 문단에 섞는다.
            let chars = [CoreHwp.HwpChar(type: .extended, value: 2), Self.fieldStart]
                + Self.textChars("ab")
                + [Self.fieldEnd, CoreHwp.HwpChar(type: .extended, value: 11)]
                + Self.textChars("cd")
            let attributed = try builtParagraph(
                chars,
                controls: [
                    .section(CoreHwp.HwpSectionDef()), Self.link,
                    .genShapeObject(HwpSynthetic.inlineShapeObject(width: 2000, height: 1000)),
                ],
                spacing: 20, alignment: .left
            )
            let string = attributed.string as NSString
            let markers = (0 ..< string.length).filter { string.character(at: $0) == 0xFFFC }
            expect(markers.count) == 4
            let line = CTLineCreateWithAttributedString(attributed)
            var verdicts: [Bool] = []
            for index in markers {
                let width = CTLineGetOffsetForStringIndex(line, index + 1, nil)
                    - CTLineGetOffsetForStringIndex(line, index, nil)
                let isControl = HwpLetterSpacing.isZeroWidthControlMarker(
                    0xFFFC, in: attributed, at: index
                )
                verdicts.append(isControl)
                expect(width == 0).to(equal(isControl), description: "\(index)")
            }
            expect(verdicts) == [true, true, true, false]
        }
    }
#endif
