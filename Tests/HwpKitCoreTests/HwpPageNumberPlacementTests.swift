@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 번호의 글자 모양과 세로 자리 (#193).
    ///
    /// 한컴오피스 한글 12.30 (macOS) 실측(2026-09-18, PDF 베이스라인): 쪽 번호는 영문 이름이
    /// "Page Number"인 스타일의 글자 모양으로 그려지고, 글자 크기 높이의 상자가 아래 위치면
    /// 꼬리말 영역 바닥, 위 위치면 머리말 영역 위에 붙는다. 베이스라인은 그 상자 바닥에서
    /// **글꼴 descent**만큼 위다 — 함초롬돋움 30pt(descent 0.23em)와 Courier New 30pt
    /// (0.30em)가 2.04pt 다르게 놓였다. 꼬리말(머리말) 여백이 0이면 상자가 아래(위) 여백의
    /// 가운데에 붙는다. 종전에는 글자 모양 0으로 꼬리말 영역 **위**에 놓아 noori에서
    /// 31.67pt 위였다.
    final class HwpPageNumberPlacementTests: XCTestCase {
        /// 꼬리말 영역 바닥 − descent — 렌더러가 그 프레임에서 그리는 베이스라인까지 잰다.
        func testBottomPageNumberSitsDescentAboveTheFooterBottom() throws {
            let geometry = Self.geometry(header: 4252, footer: 4252)
            let footer = try XCTUnwrap(geometry.footerFrame)
            let string = Self.number(size: 30)
            let baseline = Self.drawnBaseline(of: string, edge: .bottom, geometry: geometry)
            expect(baseline).to(beCloseTo(footer.maxY - Self.descent(of: string), within: 0.01))
        }

        /// 꼬리말 여백 0 — 상자 바닥이 아래 여백의 가운데 (한글: 아래 여백 30pt에서 베이스라인
        /// 819.96 = 841.86 − 15 − 6.9).
        func testFooterlessPageNumberSitsInTheMiddleOfTheBottomMargin() {
            let geometry = Self.geometry(header: 4252, footer: 0, bottom: 3000)
            let string = Self.number(size: 30)
            let baseline = Self.drawnBaseline(of: string, edge: .bottom, geometry: geometry)
            let boxBottom = geometry.pageSize.height - 15
            expect(baseline).to(beCloseTo(boxBottom - Self.descent(of: string), within: 0.01))
        }

        /// 위 위치 — 상자 위가 머리말 영역 위, 베이스라인 = 그 위 + 글자 크기 − descent (한글:
        /// 함초롬돋움 30pt 79.80 = 56.68 + 30 − 6.9). 머리말 여백 0이면 위 여백의 가운데다.
        func testTopPageNumberHangsFromTheHeaderTop() throws {
            let geometry = Self.geometry(header: 4252, footer: 4252)
            let header = try XCTUnwrap(geometry.headerFrame)
            let string = Self.number(size: 30)
            let descent = Self.descent(of: string)
            expect(Self.drawnBaseline(of: string, edge: .top, geometry: geometry))
                .to(beCloseTo(header.minY + 30 - descent, within: 0.01))

            let headerless = Self.geometry(header: 0, footer: 4252)
            expect(Self.drawnBaseline(of: string, edge: .top, geometry: headerless))
                .to(beCloseTo(headerless.margins.top / 2 + 30 - descent, within: 0.01))
        }

        /// 스타일은 영문 이름으로 찾는다 — 빈 문서의 '쪽 번호'(12번, 글자 모양 1)를 30pt로
        /// 바꾸면 쪽 번호가 30pt이고 글자 모양 id·기본 크기 표식이 실린다.
        func testPageNumberUsesTheStyleNamedPageNumber() async throws {
            let run = try await Self.pageNumberRun(index: Self.blankIndex(pageNumberCharSize: 3000))
            expect(run.fontSize).to(beCloseTo(30, within: 0.01))
            expect(run.baseFontSize).to(beCloseTo(30, within: 0.01))
            expect(run.charShapeId) == 1
        }

        /// 영문 이름이 다르면 스타일이 없는 것과 같다 — 한글 기본 모양(함초롬돋움 10pt).
        /// 한국어 이름('쪽 번호')만으로는 찾지 않는다 (한글 실측: 영문 이름만 바꾸면 기본 모양).
        func testPageNumberFallsBackWhenNoStyleHasTheEnglishName() async throws {
            let run = try await Self.pageNumberRun(
                index: Self.blankIndex(pageNumberCharSize: 3000, pageNumberEnglishName: "Other")
            )
            expect(run.fontSize).to(beCloseTo(10, within: 0.01))
            expect(run.charShapeId).to(beNil())
        }
    }

    private extension HwpPageNumberPlacementTests {
        struct PageNumberRun {
            let fontSize: CGFloat
            let baseFontSize: CGFloat?
            let charShapeId: UInt32?
        }

        /// 빈 문서 색인 — '쪽 번호' 스타일(글자 모양 1)의 크기와 영문 이름만 바꾼다.
        static func blankIndex(
            pageNumberCharSize: Int32, pageNumberEnglishName: String = "Page Number"
        ) throws -> HwpIndex {
            let base = HwpIndex(from: CoreHwp.HwpFile())
            var charShapes = base.charShapes
            charShapes[1] = CoreHwp.HwpCharShape(
                faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0],
                baseSize: pageNumberCharSize, faceColor: CoreHwp.HwpColor()
            )
            var styles = base.styles
            let key = try XCTUnwrap(
                styles.first { $0.value.styelEnglishName == "Page Number" }?.key
            )
            styles[key] = CoreHwp.HwpStyle(
                "쪽 번호", pageNumberEnglishName,
                property: 1, nextId: 0, paraShapeId: 0, charShapeId: 1
            )
            return HwpIndex(
                charShapes: charShapes, paraShapes: base.paraShapes, borderFills: base.borderFills,
                tabDefs: base.tabDefs, styles: styles, bullets: base.bullets,
                numberings: base.numberings, binData: base.binData,
                faceNamesKorean: base.faceNamesKorean, faceNamesEnglish: base.faceNamesEnglish,
                faceNamesChinese: base.faceNamesChinese, faceNamesJapanese: base.faceNamesJapanese,
                faceNamesEtc: base.faceNamesEtc, faceNamesSymbol: base.faceNamesSymbol,
                faceNamesUser: base.faceNamesUser
            )
        }

        static func geometry(
            header: UInt32, footer: UInt32, bottom: UInt32 = 4252
        ) -> HwpPageGeometry {
            var sectionDef = HwpSynthetic.sectionDef(pageHeight: 84186)
            sectionDef.pageDef.marginTop = 5668
            sectionDef.pageDef.marginBottom = bottom
            sectionDef.pageDef.marginHeader = header
            sectionDef.pageDef.marginFootnote = footer
            return HwpPageGeometry.compute(pageDef: sectionDef.pageDef, sectionDef: sectionDef)
        }

        static func number(size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: "1", attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, size, nil),
            ])
        }

        static func descent(of string: NSAttributedString) -> CGFloat {
            var descent: CGFloat = 0
            let line = CTLineCreateWithAttributedString(string)
            _ = CTLineGetTypographicBounds(line, nil, &descent, nil)
            return descent
        }

        /// 블록 프레임에서 렌더러(`HwpDrawnTextLayout.lines`)가 그리는 첫 줄 베이스라인.
        static func drawnBaseline(
            of string: NSAttributedString,
            edge: HwpPageChromeBuilder.PageNumberEdge,
            geometry: HwpPageGeometry
        ) -> CGFloat {
            let frame = HwpPageChromeBuilder.pageNumberFrame(
                of: string, edge: edge, geometry: geometry
            )
            return HwpDrawnTextLayout.lines(
                attributedString: string, origin: frame.origin, lineWidth: frame.width
            ).first?.baselineOrigin.y ?? .nan
        }

        /// 첫 쪽 쪽 번호(아래 가운데) 블록의 첫 run.
        static func pageNumberRun(index: HwpIndex) async throws -> PageNumberRun {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    HwpSynthetic.pageNumberPositionControl(
                        numberFormat: 0, displayPosition: 5, sideChar: nil
                    ),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("본문")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let block = try XCTUnwrap(page.blocks.first {
                $0.role == .pageChrome && $0.attributedString?.string == "1"
            })
            let attributes = try XCTUnwrap(
                block.attributedString?.attributes(at: 0, effectiveRange: nil)
            )
            let font = try XCTUnwrap(attributes[kCTFontAttributeName as NSAttributedString.Key])
            return PageNumberRun(
                fontSize: CTFontGetSize(font as! CTFont), // swiftlint:disable:this force_cast
                baseFontSize: (attributes[HwpAttributedStringKey.baseFontSize] as? NSNumber)
                    .map { CGFloat($0.doubleValue) },
                charShapeId: (attributes[HwpAttributedStringKey.charShapeId] as? NSNumber)
                    .map(\.uint32Value)
            )
        }
    }
#endif
