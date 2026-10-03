import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 빈칸 폭 규칙 (#249) — `HwpSpaceWidthMetrics`의 값과 MS 워드 이웃 분류표.
    ///
    /// 수치는 한글 12.30.0 build 6523 실측(2026-10-03)이다 — 20pt 기본 크기에서 한글 50%·라틴
    /// Menlo 100%의 고정 폭 5pt, 글꼴 폭 `가나 ab` 6pt·`ab cd` 12pt, 묶음 빈칸 10pt·고정폭 빈칸
    /// 5pt (`HwpRenderTuning.Text` 두 상수의 doc-comment). 조판 경로 검증은
    /// `HwpTextRunBuilderTests`의 확장(아래)에 있다.
    final class HwpSpaceWidthTests: XCTestCase {
        /// 20pt, 슬롯별 상대 크기·장평·자간을 준 글자 모양.
        private func shape(
            relativeSize: [UInt8] = [100, 100, 100, 100, 100, 100, 100],
            scaleX: [UInt8] = [100, 100, 100, 100, 100, 100, 100],
            spacing: [Int8] = [0, 0, 0, 0, 0, 0, 0]
        ) -> CoreHwp.HwpCharShape {
            CoreHwp.HwpCharShape(
                hwpxFaceId: [0, 0, 0, 0, 0, 0, 0], faceScaleX: scaleX, faceSpacing: spacing,
                faceRelativeSize: relativeSize, faceLocation: [0, 0, 0, 0, 0, 0, 0],
                baseSize: 2000, property: CoreHwp.HwpCharShapeProperty(),
                shadowIntervalX: 10, shadowIntervalY: 10, faceColor: CoreHwp.HwpColor(),
                underlineColor: CoreHwp.HwpColor(), shadeColor: CoreHwp.HwpColor(255, 255, 255),
                shadowColor: CoreHwp.HwpColor(192, 192, 192), borderFillId: 2,
                strikethroughColor: CoreHwp.HwpColor()
            )
        }

        func testFixedWidthIsHalfTheHangulSlotSize() {
            // 빈칸 자신의 슬롯(라틴)이 아니라 한글 슬롯 — 한글 50%·라틴 100%이면 5pt(10pt가
            // 아니다), 한글 100%·라틴 50%이면 10pt. 한자·기호·일어 슬롯은 무관하다.
            let hangulHalf = HwpSpaceWidthMetrics(
                shape: shape(relativeSize: [50, 100, 70, 60, 90, 80, 100])
            )
            expect(hangulHalf.fixedWidth).to(beCloseTo(5, within: 0.000_1))
            let latinHalf = HwpSpaceWidthMetrics(
                shape: shape(relativeSize: [100, 50, 100, 100, 100, 100, 100])
            )
            expect(latinHalf.fixedWidth).to(beCloseTo(10, within: 0.000_1))
        }

        func testFixedWidthFollowsTheHangulRatioButNotTheLatinRatio() {
            let hangulRatio = HwpSpaceWidthMetrics(
                shape: shape(scaleX: [50, 100, 100, 100, 100, 100, 100])
            )
            expect(hangulRatio.fixedWidth).to(beCloseTo(5, within: 0.000_1))
            let latinRatio = HwpSpaceWidthMetrics(
                shape: shape(scaleX: [100, 50, 100, 100, 100, 100, 100])
            )
            expect(latinRatio.fixedWidth).to(beCloseTo(10, within: 0.000_1))
        }

        func testSpacingKeepsItsPreviousBehaviour() {
            // 자간은 이 수정의 축이 아니다 — 고정 폭에는 종전처럼 자간이 없고, 글꼴 폭은 종전처럼
            // run 자간 kern(라틴 크기 × 라틴 자간 %)을 지닌다. 한글 자간은 어느 쪽에도 없다.
            let spaced = HwpSpaceWidthMetrics(shape: shape(spacing: [-20, 20, 0, 0, 0, 0, 0]))
            expect(spaced.latinSpacingKern).to(beCloseTo(4, within: 0.000_1))
            expect(spaced.advance(of: .ordinary)).to(beCloseTo(10, within: 0.000_1))
            expect(spaced.advance(of: .ordinary, fontWidth: 6)).to(beCloseTo(10, within: 0.000_1))
            expect(spaced.advance(of: .nonBreaking)).to(beCloseTo(10, within: 0.000_1))
            expect(spaced.advance(of: .fixedWidth)).to(beCloseTo(5, within: 0.000_1))
        }

        func testFontWidthUsesTheAssignedSlotSizeAndRatio() {
            // 라틴 글꼴 빈칸 em(Menlo 0.602)을 배정 슬롯의 크기·장평으로 키운다.
            let metrics = HwpSpaceWidthMetrics(shape: shape(
                relativeSize: [50, 100, 70, 100, 100, 100, 100],
                scaleX: [100, 50, 100, 100, 100, 100, 100]
            ))
            for (slot, width) in [(HwpScript.korean, 6.0), (.english, 6), (.chinese, 8.4)] {
                expect(metrics.fontWidth(spaceEm: 0.6, slot: slot))
                    .to(beCloseTo(width, within: 0.000_1), description: slot.rawValue)
            }
        }

        func testControlSpacesHaveTheirOwnWidths() {
            // 묶음 빈칸은 고정 폭 그대로, 고정폭 빈칸은 그 절반이다 (실측: 20pt 10pt·4.96pt,
            // 한글 50%·한글 장평 50%면 둘 다 한글 슬롯을 따라 1/4로 줄어든다).
            let plain = HwpSpaceWidthMetrics(shape: shape())
            expect(plain.advance(of: .nonBreaking)).to(beCloseTo(10, within: 0.000_1))
            expect(plain.advance(of: .fixedWidth)).to(beCloseTo(5, within: 0.000_1))
            let narrow = HwpSpaceWidthMetrics(shape: shape(
                relativeSize: [50, 100, 100, 100, 100, 100, 100],
                scaleX: [50, 100, 100, 100, 100, 100, 100]
            ))
            expect(narrow.advance(of: .nonBreaking)).to(beCloseTo(2.5, within: 0.000_1))
            expect(narrow.advance(of: .fixedWidth)).to(beCloseTo(1.25, within: 0.000_1))
        }

        private static func codePoint(_ scalar: Unicode.Scalar) -> String {
            "U+" + String(scalar.value, radix: 16, uppercase: true)
        }

        func testFontWidthGate() {
            let latin = Unicode.Scalar("a")
            let hangul = Unicode.Scalar("가")
            // '글꼴에 어울리는 빈칸'은 이웃과 무관하다.
            expect(HwpSpaceWidthMetrics.usesFontWidth(
                adjustsToFont: true, isMsWordDocument: false, previous: nil, next: nil
            )) == true
            // 한글 문서는 꺼져 있으면 언제나 고정 폭이다.
            expect(HwpSpaceWidthMetrics.usesFontWidth(
                adjustsToFont: false, isMsWordDocument: false, previous: latin, next: latin
            )) == false
            // MS 워드 호환 문서는 앞뒤가 모두 라틴 부류일 때만이다 — 이웃이 없으면(줄 시작·
            // 연속 빈칸·제어 문자) 아니다.
            expect(HwpSpaceWidthMetrics.usesFontWidth(
                adjustsToFont: false, isMsWordDocument: true, previous: latin, next: latin
            )) == true
            expect(HwpSpaceWidthMetrics.usesFontWidth(
                adjustsToFont: false, isMsWordDocument: true, previous: latin, next: hangul
            )) == false
            expect(HwpSpaceWidthMetrics.usesFontWidth(
                adjustsToFont: false, isMsWordDocument: true, previous: nil, next: latin
            )) == false
        }

        func testMsWordLatinNeighborClassification() {
            // `a X a` 282자 실측의 대표 — Word의 동아시아 힌트 Latin-1 집합과 일반 구두점은
            // 동아시아, 그리스·키릴·히브리·아랍·태국 문자와 네 따옴표는 라틴이다.
            let latin = "aZ09!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~¢£¥¦©«¬®µ»ÀéÿĀąŁœƒΑωάАяёאبก‘’“”"
            let eastAsian = "¡¤§¨ª¯°±²³´¶·¸¹º¼½¾¿×÷‐–—―‚„†•…‰′※‾⁰₁₩€℃№™"
                + "⅓Ⅰ←→∀∑−≠①─■□★♪、。「」ㄱ가あア中！Ａ０￦｡ｱ\u{1100}"
            for scalar in latin.unicodeScalars {
                expect(HwpSpaceWidthMetrics.isMsWordLatinNeighbor(scalar))
                    .to(beTrue(), description: Self.codePoint(scalar))
            }
            for scalar in eastAsian.unicodeScalars {
                expect(HwpSpaceWidthMetrics.isMsWordLatinNeighbor(scalar))
                    .to(beFalse(), description: Self.codePoint(scalar))
            }
            // 무른 하이픈도 Word 목록의 동아시아 쪽이고, 빈칸류는 이웃 글자가 아니다.
            for scalar in "\u{AD}\u{A0} ".unicodeScalars {
                expect(HwpSpaceWidthMetrics.isMsWordLatinNeighbor(scalar)) == false
            }
        }
    }

    /// 조판 경로의 빈칸 폭 (#249) — `HwpTextRunBuilder.applySpaceWidths`가 build·라벨·
    /// 독립 run에서 빈칸마다 kern을 준다. 결정론 해석기라 모든 슬롯이 Menlo(빈칸 0.602em)다.
    extension HwpTextRunBuilderTests {
        /// 글자마다 진행 폭 (pt) — 다음 글리프 원점 − 이 글리프 원점(마지막 글자는 줄 폭까지).
        /// kern이 들어간 실제 조판 폭이다. `CTLineGetOffsetForStringIndex`는 쓰지 않는다 — 캐럿
        /// 자리라 글자 사이 kern을 양쪽에 반씩 나눈다.
        private func advances(in string: NSAttributedString) -> [CGFloat] {
            Self.glyphAdvances(in: string)
        }

        static func glyphAdvances(in string: NSAttributedString) -> [CGFloat] {
            let line = CTLineCreateWithAttributedString(string)
            var origins = [CGFloat?](repeating: nil, count: string.length + 1)
            origins[string.length] = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                // 위치는 텍스트 공간 값이라 장평 행렬을 씌운다 (`FixtureSpaceWidthTests`와 같다).
                let textMatrix = CTRunGetTextMatrix(run)
                for (position, index) in zip(positions, indices) where origins[index] == nil {
                    origins[index] = position.applying(textMatrix).x
                }
            }
            return (0 ..< string.length).map { index in
                let next = origins[(index + 1)...].first { $0 != nil } ?? nil
                return (next ?? 0) - (origins[index] ?? 0)
            }
        }

        private func spaceAdvances(in string: NSAttributedString) -> [CGFloat] {
            let units = Array(string.string.utf16)
            return zip(units, advances(in: string))
                .filter { $0.0 == 0x20 || $0.0 == 0xA0 }
                .map(\.1)
        }

        private var menloSpaceEm: CGFloat {
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 100, nil)
            return HwpTextRunBuilder.spaceGlyphAdvance(of: 0x20, in: font)! / 100
        }

        private func index(
            shapes: [UInt32: CoreHwp.HwpCharShape],
            target: CoreHwp.HwpCompatibleDocumentTarget
        ) -> HwpIndex {
            HwpIndex(
                charShapes: shapes, paraShapes: [:], borderFills: [:], tabDefs: [:], styles: [:],
                bullets: [:], numberings: [:], binData: [:], faceNamesKorean: [:],
                faceNamesEnglish: [:], faceNamesChinese: [:], faceNamesJapanese: [:],
                faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:],
                isCompatibilityDocument: true, compatibleDocumentTarget: target
            )
        }

        private func build(
            _ text: String,
            shapes: [UInt32: CoreHwp.HwpCharShape],
            runs: [(UInt32, UInt32)] = [(0, 0)],
            target: CoreHwp.HwpCompatibleDocumentTarget? = nil
        ) -> NSAttributedString {
            let documentIndex = target.map { index(shapes: shapes, target: $0) }
                ?? index(shapes: shapes)
            return HwpTextRunBuilder(index: documentIndex, fontResolver: .testDeterministic)
                .build(paragraph: paragraph(text: text, runs: runs))
        }

        /// 기본 12pt(헬퍼), 한글 50%·라틴 100%.
        private func halfHangulShape(property: UInt32 = 0) throws -> CoreHwp.HwpCharShape {
            try charShape(property: property, faceRelativeSize: [50, 100, 100, 100, 100, 100, 100])
        }

        func testFixedSpaceUsesTheHangulSlotWhereverItSits() throws {
            // 한글 50%면 빈칸은 3pt — 빈칸 앞뒤가 한글이든 라틴이든 줄 시작이든 같다.
            let shapes = [UInt32(0): try halfHangulShape()]
            for text in ["가나 ab", "ab cd", " ab", "ab  cd", "漢字 漢字"] {
                for advance in spaceAdvances(in: build(text, shapes: shapes)) {
                    expect(advance).to(beCloseTo(3, within: 0.01), description: text)
                }
            }
        }

        func testFixedSpaceOverridesTheRunLetterSpacing() throws {
            // 빈칸 run의 kern(글자 모양 자간 = 크기 × %)을 빈칸 폭으로 덮어쓴다 — 라틴 자간
            // 20%여도 빈칸은 6pt다 (자간을 더하면 8.4pt가 된다).
            let shapes = [UInt32(0): try charShape(faceSpacing: [0, 20, 0, 0, 0, 0, 0])]
            let advances = spaceAdvances(in: build("ab cd", shapes: shapes))
            expect(advances.first).to(beCloseTo(6, within: 0.01))
        }

        func testFontSpaceTakesThePrecedingCharacterSlot() throws {
            // '글꼴에 어울리는 빈칸'(bit 25): 라틴 글꼴 빈칸 em × 앞 글자 슬롯 크기. 한글 뒤 6pt
            // 슬롯, 라틴 뒤·줄 시작 12pt 슬롯이고, 연속 빈칸은 앞 빈칸의 배정을 물려받는다.
            let shapes = [UInt32(0): try halfHangulShape(property: 1 << 25)]
            let spaceEm = menloSpaceEm
            expect(self.spaceAdvances(in: self.build("가나 ab", shapes: shapes)).first)
                .to(beCloseTo(spaceEm * 6, within: 0.01))
            expect(self.spaceAdvances(in: self.build("ab cd", shapes: shapes)).first)
                .to(beCloseTo(spaceEm * 12, within: 0.01))
            expect(self.spaceAdvances(in: self.build(" ab", shapes: shapes)).first)
                .to(beCloseTo(spaceEm * 12, within: 0.01))
            for advance in spaceAdvances(in: build("가나  다라", shapes: shapes)) {
                expect(advance).to(beCloseTo(spaceEm * 6, within: 0.01))
            }
        }

        func testLongSpaceRunsInheritTheAssignmentInOnePass() throws {
            // 연속 빈칸은 앞 빈칸의 배정을 물려받는다 — 직전 빈칸의 배정을 기억해(`AssignedSlotMemo`)
            // 빈칸마다 앞 빈칸들을 다시 거슬러 올라가지 않는다. 4,000개가 모두 한글 배정이어야 한다.
            let shapes = [UInt32(0): try halfHangulShape(property: 1 << 25)]
            let text = "가" + String(repeating: " ", count: 4000) + "ab"
            let advances = spaceAdvances(in: build(text, shapes: shapes))
            expect(advances.count) == 4000
            let expected = menloSpaceEm * 6
            expect(advances.allSatisfy { abs($0 - expected) < 0.01 }) == true
        }

        func testFontSpaceAtACharShapeBoundaryIsLatin() throws {
            // 같은 글자 모양 run 안의 앞 글자만 본다 — 빈칸이 새 run을 열면 줄 시작처럼 라틴
            // (실측: `가나` + ` ab`(다른 글자 모양)의 빈칸이 라틴 슬롯 폭).
            let shape = try halfHangulShape(property: 1 << 25)
            let advances = spaceAdvances(in: build(
                "가나 ab", shapes: [0: shape, 1: shape], runs: [(0, 0), (2, 1)]
            ))
            expect(advances.first).to(beCloseTo(menloSpaceEm * 12, within: 0.01))
        }

        func testFontSpaceSkipsMarksAndRecombinesSurrogates() throws {
            // 배정은 결합 부호를 건너뛰어 그 앞 글자를 보고(`가\u{301} ab` → 한글), 보충 평면
            // 글자는 대리 쌍을 묶어 판정한다(`𠀀 ab` → 한자 70%). 한글 50%·라틴 100%·한자 70%.
            let shapes = [UInt32(0): try charShape(
                property: 1 << 25, faceRelativeSize: [50, 100, 70, 100, 100, 100, 100]
            )]
            let spaceEm = menloSpaceEm
            expect(self.spaceAdvances(in: self.build("가\u{301} ab", shapes: shapes)).first)
                .to(beCloseTo(spaceEm * 6, within: 0.01))
            expect(self.spaceAdvances(in: self.build("\u{20000} ab", shapes: shapes)).first)
                .to(beCloseTo(spaceEm * 8.4, within: 0.01))
        }

        func testFontSpaceKeepsTheRunLetterSpacing() throws {
            // 글꼴 폭 빈칸은 종전처럼 run의 자간 kern을 지닌다 — 라틴 자간 −10%면 Menlo 빈칸 × 12pt에서
            // 1.2pt를 뺀 폭. 고정 폭 빈칸에는 자간이 없다.
            let spacing: [Int8] = [0, -10, 0, 0, 0, 0, 0]
            let fontShapes = [UInt32(0): try charShape(property: 1 << 25, faceSpacing: spacing)]
            expect(self.spaceAdvances(in: self.build("ab cd", shapes: fontShapes)).first)
                .to(beCloseTo(menloSpaceEm * 12 - 1.2, within: 0.01))
            let fixedShapes = [UInt32(0): try charShape(faceSpacing: spacing)]
            expect(self.spaceAdvances(in: self.build("ab cd", shapes: fixedShapes)).first)
                .to(beCloseTo(6, within: 0.01))
        }

        func testBulletHeadingSpaceIsOutsideThePass() throws {
            // 글머리표 머리 `□ `의 빈칸은 본문 글자가 아니라 패스 범위 밖이다 — 종전대로 글꼴 폭을
            // 지키고(결정론 해석기의 Menlo 10pt 빈칸), 본문 빈칸만 0.5em(5pt)이 된다.
            let bullet = CoreHwp.HwpBullet(
                hwpxInfo: [UInt8](repeating: 0, count: 8), headCharShapeId: -1,
                char: "□", checkChar: ""
            )
            let index = try HwpNumberingHeadingRenderTests.index(
                paraShape: CoreHwp.HwpParaShape(
                    property1: 3 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 1
                ),
                bullets: [0: bullet]
            )
            let builder = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
            let attributed = builder.build(
                paragraph: try HwpNumberingHeadingRenderTests.paragraph("가 나", runs: [(0, 0)]),
                number: nil
            )
            expect(attributed.string) == "□ 가 나"
            let advances = spaceAdvances(in: attributed)
            expect(advances.count) == 2
            expect(advances[0]).to(beCloseTo(menloSpaceEm * 10, within: 0.01))
            expect(advances[1]).to(beCloseTo(5, within: 0.01))
        }

        func testNumberingLabelSpacesFollowTheRule() throws {
            // 번호 형식의 빈칸(`제 ^1 장`)도 본문 빈칸과 같은 규칙이다 — 라벨 글자 모양(문단 마지막
            // 글자 12pt)의 0.5em = 6pt. 거리 빈칸은 정의가 정한 폭(0.5em = 6pt)을 그대로 지닌다.
            let number = HwpParagraphNumber(
                kind: .outline, definitionIndex: 0, numbers: [1], text: "제 1 장"
            )
            let attributed = try HwpNumberingHeadingRenderTests.build(
                "가나", runs: [(0, 1)],
                definition: HwpNumberingHeadingRenderTests.definition(format: "제 ^1 장"),
                number: number
            )
            expect(attributed.string) == "제 1 장 가나"
            for advance in spaceAdvances(in: attributed) {
                expect(advance).to(beCloseTo(6, within: 0.01))
            }
        }

        func testMsWordSpaceBetweenLatinCharactersFollowsTheFont() throws {
            // MS 워드 호환 문서: 앞뒤가 모두 라틴 부류면 글꼴 폭, 아니면 한글 문서와 같은 고정
            // 폭이다 — 연속 빈칸과 동아시아 힌트 기호(½) 옆은 고정 폭.
            let shapes = [UInt32(0): try halfHangulShape()]
            let font = menloSpaceEm * 12
            for text in ["ab cd", "ab, cd"] {
                let advances = spaceAdvances(in: build(text, shapes: shapes, target: .msWord))
                expect(advances.first).to(beCloseTo(font, within: 0.01), description: text)
            }
            for text in ["가나 ab", "ab 가나", " ab", "ab  cd", "ab ½ cd"] {
                for advance in spaceAdvances(in: build(text, shapes: shapes, target: .msWord)) {
                    expect(advance).to(beCloseTo(3, within: 0.01), description: text)
                }
            }
        }

        func testMsWordNeighborCrossesCharShapeRuns() throws {
            // 이웃은 글자 모양 경계를 넘어 실제로 맞닿은 글자다 (실측: `ab` + ` cd`).
            let shape = try halfHangulShape()
            let advances = spaceAdvances(in: build(
                "ab cd", shapes: [0: shape, 1: shape], runs: [(0, 0), (2, 1)], target: .msWord
            ))
            expect(advances.first).to(beCloseTo(menloSpaceEm * 12, within: 0.01))
        }

        func testHwp2007DocumentKeepsTheFixedSpace() throws {
            // 한글 2007 호환 문서는 한글 문서와 같다 — 종전에는 호환 문서 전체를 글꼴 폭으로
            // 돌려 이 갈래가 틀렸다.
            let shapes = [UInt32(0): try halfHangulShape()]
            let advances = spaceAdvances(in: build("ab cd", shapes: shapes, target: .hwp200X))
            expect(advances.first).to(beCloseTo(3, within: 0.01))
        }

        func testNonBreakingAndFixedWidthSpaces() throws {
            // 묶음 빈칸(30) = 고정 폭, 고정폭 빈칸(31) = 그 절반 — 둘 다 U+00A0인데 표식으로 갈린다.
            let shapes = [UInt32(0): try halfHangulShape()]
            let advances = spaceAdvances(in: build("ab\u{1E}cd\u{1F}ef", shapes: shapes))
            expect(advances.count) == 2
            expect(advances[0]).to(beCloseTo(3, within: 0.01))
            expect(advances[1]).to(beCloseTo(1.5, within: 0.01))
        }

        func testSpaceAfterAControlSpaceHasNoNeighbor() throws {
            // 묶음·고정폭 빈칸은 한글에서 제어 문자다 — 뒤 빈칸의 이웃·배정이 되지 않는다
            // (실측: `가나<묶음> ab`의 빈칸이 글꼴 빈칸에서 라틴, MS 워드에서 고정 폭).
            let fontShapes = [UInt32(0): try halfHangulShape(property: 1 << 25)]
            let afterControl = spaceAdvances(in: build("가나\u{1E} ab", shapes: fontShapes))
            expect(afterControl.last).to(beCloseTo(menloSpaceEm * 12, within: 0.01))
            let wordShapes = [UInt32(0): try halfHangulShape()]
            let msWord = spaceAdvances(
                in: build("ab\u{1F} cd", shapes: wordShapes, target: .msWord)
            )
            expect(msWord.last).to(beCloseTo(3, within: 0.01))
        }

        func testRangeBoundsTheNeighbors() throws {
            // 범위 밖 글자는 이웃이 아니다 — 문단 머리(라벨) 뒤 본문 첫 빈칸은 줄 시작과 같다.
            let shapes = [UInt32(0): try halfHangulShape()]
            let builder = HwpTextRunBuilder(
                index: index(shapes: shapes, target: .msWord), fontResolver: .testDeterministic
            )
            let built = NSMutableAttributedString(attributedString: builder.build(
                paragraph: paragraph(text: "ab cd", runs: [(0, 0)])
            ))
            builder.applySpaceWidths(to: built, in: NSRange(location: 2, length: 3))
            expect(self.spaceAdvances(in: built).first).to(beCloseTo(3, within: 0.01))
        }

        func testMarkedSpacesAreLeftAlone() throws {
            // 문단 번호 거리 빈칸·컨트롤 치환·빈 줄 앵커는 자기 폭을 이미 정했다.
            let builder = HwpTextRunBuilder(
                index: index(shapes: [0: try halfHangulShape()]), fontResolver: .testDeterministic
            )
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil)
            for key in [
                HwpAttributedStringKey.numberingLabel, HwpAttributedStringKey.controlIndex,
                HwpAttributedStringKey.emptyLineAnchor,
            ] {
                let marked = NSMutableAttributedString(string: "a b", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    HwpAttributedStringKey.charShapeId: NSNumber(value: 0),
                    key: NSNumber(value: true),
                ])
                builder.applySpaceWidths(to: marked)
                expect(marked.attribute(
                    kCTKernAttributeName as NSAttributedString.Key, at: 1, effectiveRange: nil
                )).to(beNil(), description: key.rawValue)
            }
        }

        func testStandaloneRunAndNumberingFollowTheSameRule() throws {
            // 쪽 번호 같은 독립 run도 같은 패스를 지난다 — `- 1 -`의 빈칸이 한글 슬롯 반 폭.
            let builder = HwpTextRunBuilder(
                index: index(shapes: [0: try halfHangulShape()]), fontResolver: .testDeterministic
            )
            for advance in spaceAdvances(in: builder.standaloneRun("- 1 -", charShapeId: 0)) {
                expect(advance).to(beCloseTo(3, within: 0.01))
            }
        }
    }
#endif
