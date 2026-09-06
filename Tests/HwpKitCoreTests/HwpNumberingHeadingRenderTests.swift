@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 번호·개요 번호 라벨 전치 (#154) — 글자 모양·스크립트 슬롯·빈 라벨·빈
    /// 문단·글머리표 불변·진단 제외·조판기 통합을 합성 입력으로 잠근다. 기하(번호
    /// 너비·정렬·거리·자동 내어쓰기·이어지는 조각)는 같은 헬퍼를 쓰는
    /// `HwpNumberingHeadingLayoutTests`가, 실물 대조는 `HwpKitTests`의 픽스처
    /// 스위트(헌법주석 13쪽·`outline-numbering`·`numbering-sequence`)가 맡는다.
    final class HwpNumberingHeadingRenderTests: XCTestCase {
        /// 글자 모양 0 = 10pt(바탕글 상당), 1 = 12pt(제목 상당).
        static let sizes: [UInt32: Int32] = [0: 1000, 1: 1200]

        static func charShape(baseSize: Int32) throws -> CoreHwp.HwpCharShape {
            var data = Data()
            func append(_ value: some FixedWidthInteger) {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            for _ in 0 ..< 7 {
                append(UInt16(0))
            } // faceId
            data.append(contentsOf: [UInt8](repeating: 100, count: 7)) // faceScaleX
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // faceSpacing
            data.append(contentsOf: [UInt8](repeating: 100, count: 7)) // faceRelativeSize
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // faceLocation
            append(baseSize)
            append(UInt32(0)) // property
            data.append(contentsOf: [0, 0]) // shadow offsets
            for _ in 0 ..< 4 {
                append(UInt32(0))
            } // colors
            return try CoreHwp.HwpCharShape.load(data, CoreHwp.HwpVersion(5, 0, 1, 0))
        }

        /// 정의 하나(형식 `^1.`, 로마 대문자)와 개요 1수준 문단 모양 1을 담은 사전.
        static func index(
            definition: CoreHwp.HwpNumbering = definition(),
            paraShape: CoreHwp.HwpParaShape = HwpSynthetic.outlineParaShape(levelRawValue: 0),
            bullets: [UInt32: CoreHwp.HwpBullet] = [:]
        ) throws -> HwpIndex {
            HwpIndex(
                charShapes: try sizes.mapValues(charShape(baseSize:)),
                paraShapes: [1: paraShape],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: bullets,
                numberings: [0: definition], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }

        static func definition(
            alignment: CoreHwp.HwpParaHeadAlignment = .left,
            useInstWidth: Bool = true,
            autoIndent: Bool = true,
            textOffsetType: CoreHwp.HwpParaHeadTextOffsetType = .percent,
            textOffset: Int16 = 50,
            widthAdjust: Int16 = 0,
            charShapeId: Int32 = -1,
            format: String = "^1."
        ) -> CoreHwp.HwpNumbering {
            CoreHwp.HwpNumbering(
                formatArray: [CoreHwp.HwpNumberingFormat(
                    property: CoreHwp.HwpParaHeadInfo(
                        alignment: alignment, useInstWidth: useInstWidth, autoIndent: autoIndent,
                        textOffsetType: textOffsetType, numberFormat: 2,
                        widthAdjust: widthAdjust, textOffset: textOffset, charShapeId: charShapeId
                    ).bytes,
                    formatLength: WORD(format.utf16.count),
                    format: format
                )],
                startingIndex: 1, startingIndexArray: nil,
                extendedFormatArray: nil, extendedStartingIndexArray: nil
            )
        }

        /// 문단 모양 1의 개요 문단 — 글자 모양 run은 `(시작 위치, 모양 id)`.
        static func paragraph(
            _ text: String, runs: [(UInt32, UInt32)]
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.styledParagraph(text, paraShapeId: 1)
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = runs.map(\.0)
            paraCharShape.shapeId = runs.map(\.1)
            paragraph.paraCharShape = paraCharShape
            return paragraph
        }

        static let roman = HwpParagraphNumber(
            kind: .outline, definitionIndex: 0, numbers: [1], text: "I."
        )

        static func build(
            _ text: String = "가나", runs: [(UInt32, UInt32)] = [(0, 0), (1, 1)],
            definition: CoreHwp.HwpNumbering = definition(),
            number: HwpParagraphNumber? = roman
        ) throws -> NSAttributedString {
            HwpTextRunBuilder(
                index: try index(definition: definition), fontResolver: .testDeterministic
            ).build(paragraph: try paragraph(text, runs: runs), number: number)
        }

        static func font(at location: Int, in attributed: NSAttributedString) -> CTFont? {
            let value = attributed.attribute(
                kCTFontAttributeName as NSAttributedString.Key, at: location, effectiveRange: nil
            )
            guard let value, CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else {
                return nil
            }
            // swiftlint:disable:next force_cast
            return (value as! CTFont)
        }

        static func kern(at location: Int, in attributed: NSAttributedString) -> CGFloat {
            let value = attributed.attribute(
                kCTKernAttributeName as NSAttributedString.Key, at: location, effectiveRange: nil
            ) as? NSNumber
            return CGFloat(value?.doubleValue ?? 0)
        }

        static func labelRange(in attributed: NSAttributedString) -> NSRange? {
            var range = NSRange(location: NSNotFound, length: 0)
            let value = attributed.attribute(
                HwpAttributedStringKey.numberingLabel, at: 0,
                longestEffectiveRange: &range, in: NSRange(location: 0, length: attributed.length)
            )
            return value == nil ? nil : range
        }

        static func styleValue(
            _ specifier: CTParagraphStyleSpecifier, in attributed: NSAttributedString
        ) -> CGFloat {
            let value = attributed.attribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key, at: 0, effectiveRange: nil
            )
            guard let value else { return .nan }
            let style = value as! CTParagraphStyle // swiftlint:disable:this force_cast
            var result: CGFloat = 0
            CTParagraphStyleGetValueForSpecifier(
                style, specifier, MemoryLayout<CGFloat>.size, &result
            )
            return result
        }

        /// 문자열 인덱스가 시작하는 글리프의 줄-내 x — 캐럿 오프셋과 달리 kern을 나누지
        /// 않는다.
        static func glyphX(ofStringIndex index: Int, in line: CTLine) -> CGFloat? {
            // swiftlint:disable:next force_cast
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let range = CTRunGetStringRange(run)
                guard range.location <= index, index < range.location + range.length
                else { continue }
                var positions = [CGPoint](repeating: .zero, count: CTRunGetGlyphCount(run))
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                return positions[index - range.location].x
            }
            return nil
        }

        /// 빈칸 한 자의 목표 폭 = 글리프 advance + kern.
        static func spaceWidth(
            at location: Int, in attributed: NSAttributedString
        ) throws -> CGFloat {
            let font = try XCTUnwrap(font(at: location, in: attributed))
            return HwpTextRunBuilder.glyphAdvance(of: 0x20, in: font)
                + kern(at: location, in: attributed)
        }

        // MARK: - 라벨·글자 모양·거리

        /// 기본 정의(왼쪽·자릿수 맞춤·비율 50%·글자 모양 -1): 라벨 + 0.5em 빈칸이
        /// 전치되고, 글자 모양은 문단 **맨 마지막** 글자(12pt)를 따른다 — 첫 글자
        /// (10pt)도 바탕글도 아니다 (한컴 도움말).
        func testLabelFollowsLastCharacterShapeAndHalfEmGap() throws {
            let attributed = try Self.build()

            expect(attributed.string) == "I. 가나"
            expect(Self.labelRange(in: attributed)) == NSRange(location: 0, length: 3)
            expect(attributed.attribute(
                HwpAttributedStringKey.numberingLabel, at: 3, effectiveRange: nil
            )).to(beNil())
            expect(Self.font(at: 0, in: attributed).map(CTFontGetSize)) == 12
            expect(Self.font(at: 3, in: attributed).map(CTFontGetSize)) == 10
            expect(try Self.spaceWidth(at: 2, in: attributed)).to(beCloseTo(6, within: 0.01))
        }

        /// 라벨은 글자마다 스크립트 슬롯을 판정한다 — `(나)`의 괄호는 영문 슬롯, `나`는
        /// 한글 슬롯 글꼴이고 거리 빈칸은 본문 빈칸처럼 영문 슬롯이다. 슬롯별 글꼴이
        /// 갈리도록 사전에 face 이름을 싣고 시스템 조회 resolver를 쓴다.
        func testLabelSwitchesScriptSlotsPerCharacter() throws {
            let index = HwpIndex(
                charShapes: [0: try Self.charShape(baseSize: 1000)],
                paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:],
                numberings: [0: Self.definition()], binData: [:],
                faceNamesKorean: [
                    0: CoreHwp.HwpFaceName(hwpxFace: "Apple SD Gothic Neo", substituteFace: nil),
                ],
                faceNamesEnglish: [0: CoreHwp.HwpFaceName(hwpxFace: "Menlo", substituteFace: nil)],
                faceNamesChinese: [:], faceNamesJapanese: [:], faceNamesEtc: [:],
                faceNamesSymbol: [:], faceNamesUser: [:]
            )
            let number = HwpParagraphNumber(
                kind: .outline, definitionIndex: 0, numbers: [1], text: "(나)"
            )
            let attributed = HwpTextRunBuilder(
                index: index, fontResolver: HwpFontResolver(usesInstalledHancomFonts: false)
            ).build(paragraph: try Self.paragraph("본문", runs: [(0, 0)]), number: number)

            expect(attributed.string) == "(나) 본문"
            let families = (0 ..< 4).map { location in
                Self.font(at: location, in: attributed).map { CTFontCopyFamilyName($0) as String }
            }
            expect(families[0]) == "Menlo"
            expect(families[1]) == "Apple SD Gothic Neo"
            expect(families[2]) == "Menlo"
            expect(families[3]) == "Menlo"
        }

        /// 정의가 실재하는 글자 모양을 가리키면 그것을 쓰고, 사전에 없는 id는 -1과
        /// 같이 마지막 글자로 돌아간다.
        func testDefinitionCharShapeWinsOnlyWhenItExists() throws {
            let explicit = try Self.build(definition: Self.definition(charShapeId: 0))
            expect(Self.font(at: 0, in: explicit).map(CTFontGetSize)) == 10

            let dangling = try Self.build(definition: Self.definition(charShapeId: 7))
            expect(Self.font(at: 0, in: dangling).map(CTFontGetSize)) == 12
        }

        /// 번호가 없는 문단은 글머리표 경로가 그대로다 — 글머리표 문단(머리 종류 3,
        /// 정의 1)에 `number: nil`이면 종전대로 `□ `가 전치되고 라벨 표식은 없다.
        func testBulletParagraphStillGetsItsBulletWithoutANumber() throws {
            let bullet = CoreHwp.HwpBullet(
                hwpxInfo: [UInt8](repeating: 0, count: 8), headCharShapeId: -1,
                char: "□", checkChar: ""
            )
            let index = try Self.index(
                paraShape: CoreHwp.HwpParaShape(
                    property1: 3 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 1
                ),
                bullets: [0: bullet]
            )
            let attributed = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: try Self.paragraph("가나", runs: [(0, 0)]), number: nil)

            expect(attributed.string) == "□ 가나"
            expect(attributed.attribute(
                HwpAttributedStringKey.numberingLabel, at: 0, effectiveRange: nil
            )).to(beNil())
        }

        /// 글자가 없는 개요 문단(PARA_TEXT 없음)도 라벨을 받는다 — 번호는 문단
        /// 모양·구역 정의로 매겨지므로 빈 개요 줄이 번호만 삼키고 사라지면 안 된다.
        /// 번호가 없는 빈 문단은 종전대로 빈 문단 앵커다 (#145).
        func testEmptyParagraphStillReceivesItsLabel() throws {
            let labelled = try Self.build("", runs: [(0, 1)])
            expect(labelled.string) == "I. "
            expect(Self.labelRange(in: labelled)) == NSRange(location: 0, length: 3)
            expect(HwpTextRunBuilder.isEmptyParagraphAnchor(labelled)) == false

            let anchor = try Self.build("", runs: [(0, 1)], number: nil)
            expect(HwpTextRunBuilder.isEmptyParagraphAnchor(anchor)) == true
        }

        /// 빈 라벨(형식 슬롯 없음)은 아무것도 전치하지 않고, 번호가 없으면 글머리표
        /// 경로만 남아 본문이 그대로다.
        func testEmptyLabelAndMissingNumberPrefixNothing() throws {
            let empty = try Self.build(number: HwpParagraphNumber(
                kind: .outline, definitionIndex: 0, numbers: [1], text: ""
            ))
            expect(empty.string) == "가나"
            expect(Self.labelRange(in: empty)).to(beNil())

            let none = try Self.build(number: nil)
            expect(none.string) == "가나"
        }

        /// 오른쪽 정렬·자릿수 맞춤 해제·너비 조정 30pt·HWPUNIT 거리 10pt: 번호 너비는
        /// 글자 크기(마지막 글자 12pt)의 1.5배 + 30pt이고 라벨 앞 남은 폭은 글자가
        /// 아니라 첫 줄 들여쓰기이며 거리는 절대값이다. 자동 내어쓰기가 꺼져 있어 둘째
        /// 줄은 여백에 남는다.
        func testRightAlignedFixedWidthUsesHwpUnitOffset() throws {
            let attributed = try Self.build(definition: Self.definition(
                alignment: .right, useInstWidth: false, autoIndent: false,
                textOffsetType: .hwpUnit, textOffset: 1000, widthAdjust: 3000
            ))

            expect(attributed.string) == "I. 가나"
            expect(Self.labelRange(in: attributed)) == NSRange(location: 0, length: 3)
            let labelWidth = HwpTextRunBuilder.typographicWidth(
                of: attributed.attributedSubstring(from: NSRange(location: 0, length: 2))
            )
            expect(Self.styleValue(.firstLineHeadIndent, in: attributed))
                .to(beCloseTo(18 + 30 - labelWidth, within: 0.01))
            expect(try Self.spaceWidth(at: 2, in: attributed)).to(beCloseTo(10, within: 0.01))
            expect(attributed.attribute(
                HwpAttributedStringKey.numberingHeadIndent, at: 0, effectiveRange: nil
            )).to(beNil())
            expect(Self.styleValue(.headIndent, in: attributed)) == 0
        }

        // MARK: - 조판기 통합

        /// 쪽 경계: 라벨 문단이 두 쪽에 걸쳐도 라벨은 첫 쪽의 첫 조각에 한 번뿐이고,
        /// 다음 쪽의 조각은 본문만 잇는다. 뒤따르는 문단의 번호는 정상적으로 다음 값이다.
        func testLabelAppearsOnceWhenParagraphSpansPages() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try Self.paragraph(String(repeating: "가나다라마바사 ", count: 240), runs: [(0, 0)]),
                    try Self.paragraph("둘째", runs: [(0, 0)]),
                ],
                index: try Self.index(),
                pageHeight: 30000
            )
            let pageCount = await paginator.totalPages()
            expect(pageCount) >= 2

            var labelled: [(page: Int, text: String)] = []
            var fragmentPages: [Int] = []
            for pageIndex in 0 ..< pageCount {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks {
                    guard let text = block.attributedString, text.string.contains("가나다라마바사")
                    else { continue }
                    fragmentPages.append(pageIndex)
                    let marked = text.attribute(
                        HwpAttributedStringKey.numberingLabel, at: 0, effectiveRange: nil
                    )
                    if marked != nil {
                        labelled.append((pageIndex, String(text.string.prefix(3))))
                    }
                }
            }
            // 조각이 둘 이상의 쪽에 걸치고, 라벨은 첫 조각(첫 쪽)에만 있다.
            expect(Set(fragmentPages).count) >= 2
            expect(labelled.map(\.page)) == [fragmentPages.first]
            expect(labelled.map(\.text)) == ["I. "]
            // 이어지는 쪽의 조각은 첫 줄부터 자동 내어쓰기 x에서 시작한다 — 조각을
            // 독립 프레임으로 다시 조판해도 첫 줄 들여쓰기로 돌아가지 않는다.
            let lastPage = try await paginator.page(at: pageCount - 1)
            let continuation = try XCTUnwrap(lastPage?.blocks.first {
                $0.attributedString?.string.contains("가나다라마바사") == true
            })
            let text = try XCTUnwrap(continuation.attributedString)
            let lines = HwpDrawnTextLayout.lines(
                attributedString: text, origin: .zero, lineWidth: continuation.frame.width
            )
            expect(lines.count) >= 2
            expect(lines[0].baselineOrigin.x) == lines[1].baselineOrigin.x
            expect(lines[0].baselineOrigin.x) > 10
            let last = try await paginator.page(at: pageCount - 1)
            expect(last?.blocks.compactMap { $0.attributedString?.string }.last) == "II. 둘째"
        }

        /// 조판기는 최상위 문단마다 `paragraphNumbering`의 번호를 넘겨 라벨을 전치하고,
        /// 라벨을 그린 문단은 미지원 진단에서 빠진다. 복사·낭독 소스인 선택 단위와
        /// 접근성 단위에도 라벨이 실린다.
        func testPaginatorPrefixesLabelsAndSkipsTheDiagnostic() async throws {
            let index = try Self.index()
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try Self.paragraph("첫째", runs: [(0, 1)]),
                    try Self.paragraph("둘째", runs: [(0, 0)]),
                ],
                index: index
            )

            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            // 구역 정의 문단(컨트롤 마커뿐)은 뺀다.
            let isBody: (String) -> Bool = { $0.contains { $0 != "\u{FFFC}" } }
            let texts = page.blocks.compactMap { $0.attributedString?.string }.filter(isBody)
            expect(texts) == ["I. 첫째", "II. 둘째"]
            let hints = await paginator.unsupportedElements().map(\.hint)
            expect(hints).to(beEmpty())

            let units = HwpSelectableText.units(in: page)
            expect(units.map(\.attributedString.string).filter(isBody)) == ["I. 첫째", "II. 둘째"]
            let spoken = HwpAccessibilityContent.pageUnits(page: page, bodyUnits: units)
                .map(\.label)
            expect(spoken).to(contain("I. 첫째"))
        }
    }
#endif
