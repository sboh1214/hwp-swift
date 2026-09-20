@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 컨테이너(표 셀·글상자) 내용 범위 = 첫 문단 위 간격부터 마지막 줄 **상자** 아래까지 (#193).
    ///
    /// 기대값은 한컴오피스 한글 12.30 (macOS) 합성 문서 실측(2026-09-18)이다 — 40pt 셀·안쪽 여백
    /// 1.41pt·10pt 한 줄에서 한글 PDF의 베이스라인이 셀 위에서 가운데 23.52·아래 37.08(줄 간격
    /// 160%·300%·고정 20pt·아래 간격 10pt 모두 같다), 위 간격 10pt 가운데 28.56이다. 베이스라인은
    /// 줄 상자 상단 + 8.5이므로 상자 상단은 15.02·28.58·20.06 — 아래 기대값(15.00·28.59·20.00)과
    /// PDF 양자화(0.12pt) 안에서 같다. 종전에는 줄 간격 여분과 아래 간격을 내용에 넣어 가운데
    /// 정렬이 (여분 + 아래 간격)/2, 아래 정렬이 그 전부만큼 위에 놓였다.
    final class HwpContainerContentExtentTests: XCTestCase {
        // MARK: 표 셀

        func testCenteredCellCentersTheLastLineBoxWithoutItsLineSpacing() throws {
            // 캐시 줄 1000·줄 간격 600: 안쪽 37.18에서 상자 10을 가운데 → 1.41 + 13.59.
            let rect = try cellParagraphRect(alignment: .center, paragraphs: [oneLine()])
            expect(rect.minY).to(beCloseTo(15.00, within: 0.01))
        }

        func testBottomCellPutsTheLastLineBoxOnTheInnerBottom() throws {
            let rect = try cellParagraphRect(alignment: .bottom, paragraphs: [oneLine()])
            expect(rect.minY + 10).to(beCloseTo(40 - 1.41, within: 0.01))
        }

        /// 마지막 문단의 아래 간격도 범위 밖이다 (한글 T5·T6: 아래 간격 10pt여도 같은 자리).
        func testSpacingAfterTheLastParagraphDoesNotShiftAlignment() throws {
            let center = try cellParagraphRect(
                alignment: .center, paragraphs: [oneLine()], spacingBottom: 2000
            )
            expect(center.minY).to(beCloseTo(15.00, within: 0.01))
            let bottom = try cellParagraphRect(
                alignment: .bottom, paragraphs: [oneLine()], spacingBottom: 2000
            )
            expect(bottom.minY + 10).to(beCloseTo(40 - 1.41, within: 0.01))
        }

        /// 첫 문단 위 간격은 범위에 든다 — 범위 20(위 10 + 상자 10)을 가운데 두고 상자는 위 간격
        /// 아래다: 1.41 + (37.18 − 20)/2 + 10.
        func testSpacingBeforeTheFirstParagraphCountsTowardAlignment() throws {
            let rect = try cellParagraphRect(
                alignment: .center, paragraphs: [oneLine()], spacingTop: 2000
            )
            expect(rect.minY).to(beCloseTo(20.00, within: 0.01))
        }

        /// 두 문단은 둘째 문단의 마지막 줄 상자까지다 — 1600 + 1000 = 26pt를 안쪽 57.18에서
        /// 가운데 → 첫 문단 상단 1.41 + 15.59.
        func testTwoParagraphsCenterUpToTheSecondParagraphBox() throws {
            let rects = try cellParagraphRects(
                alignment: .center,
                paragraphs: [
                    oneLine(),
                    HwpSynthetic.lineSegParagraph("나", segments: [(location: 1600, height: 1000)]),
                ],
                height: 6000
            )
            expect(rects.first?.minY).to(beCloseTo(17.00, within: 0.01))
            expect(rects.last?.minY).to(beCloseTo(33.00, within: 0.01))
        }

        /// 내용이 행 높이를 정하는 셀도 같은 범위다 — 한글은 저작 282 셀에 아래 간격 10pt 문단
        /// 하나를 12.82pt(상자 10 + 안쪽 여백)로 그린다 (#193 실측 RH1; 종전 22.82).
        func testCachedRowFloorExcludesTheLastParagraphSpacingAfter() throws {
            let frame = try cellTable(
                alignment: .top, paragraphs: [oneLine()], height: 282, spacingBottom: 2000
            )
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))
        }

        /// 캐시 없는(CT로 잰) 셀도 마지막 줄 상자에서 끝난다 — 줄 간격 여분(160% → 6pt)이 행에
        /// 들지 않아 12.82pt이고, 가운데 정렬에 남는 여유가 없어 글자가 위에 붙는다.
        func testUncachedCellRowEndsAtTheLastLineBox() throws {
            let frame = try cellTable(
                alignment: .center, paragraphs: [HwpSynthetic.textParagraph("가")], height: 282
            )
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))
            expect(frame.rows[0].cells[0].paragraphs.first?.rect.minY)
                .to(beCloseTo(1.41, within: 0.01))
        }

        /// 줄 전진량이 상자보다 작으면(비율 60% → 6pt < 상자 10pt) 내용 범위는 전진량 끝이
        /// 아니라 상자 바닥까지다 — 캐시 없는 CT 셀·글상자도 한글이 저장한 캐시(`vertsize`
        /// 1000·`spacing` −400)로 잰 셀과 같은 답이어야 한다 (PR 리뷰: 4pt 갈렸다).
        func testLineAdvanceShorterThanTheBoxStillEndsAtTheBoxBottom() throws {
            let uncached = try cellTable(
                alignment: .bottom, paragraphs: [HwpSynthetic.textParagraph("가")],
                height: 4000, lineSpacing: 60
            )
            let uncachedRect = try XCTUnwrap(uncached.rows[0].cells[0].paragraphs.first?.rect)
            expect(uncachedRect.minY + 10).to(beCloseTo(40 - 1.41, within: 0.01))

            let floor = try cellTable(
                alignment: .top, paragraphs: [HwpSynthetic.textParagraph("가")],
                height: 282, lineSpacing: 60
            )
            expect(floor.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))

            let box = try textboxParagraphRect(alignment: .bottom, lineSpacing: 60)
            expect(box.minY + 10).to(beCloseTo(40 - 2.83, within: 0.01))
            let centered = try textboxParagraphRect(alignment: .center, lineSpacing: 60)
            expect(centered.minY).to(beCloseTo(15.00, within: 0.01))
        }

        /// 겹친 줄(고정 줄 간격 16pt < 첫 줄 상자 30pt)에서도 기준은 **마지막 줄 상자**다 —
        /// 앞 줄이 더 아래까지 내려가도 한글은 그 줄을 셀 밖으로 흘려 보낸다. 캐시 경로와 CT
        /// 경로가 같은 자리를 내야 한다 (#193 리뷰, 한컴오피스 한글 12.30 실측 2026-09-20:
        /// 30pt + 10pt 두 줄·고정 16pt 셀에서 아래 정렬 첫 줄 베이스라인이 셀 위 + 38.16(셀
        /// 아래로 4pt 넘침)·가운데 정렬 32.52, 저작 282 행이 28.80pt. 줄 상자 최댓값을 쓰면
        /// 34.16·30.52·32.82로 4pt 어긋난다).
        func testOverlappingLinesEndAtTheLastLineBoxInBothPaths() throws {
            for cached in [false, true] {
                let paragraph = try Self.overlappingParagraph(cached: cached)
                let bottom = try cellTable(
                    alignment: .bottom, paragraphs: [paragraph], height: 4000,
                    index: Self.overlappingIndex()
                )
                let bottomRect = try XCTUnwrap(bottom.rows[0].cells[0].paragraphs.first?.rect)
                // 마지막 줄(10pt) 상자 아래가 안쪽 아래에 닿고, 첫 줄(30pt)은 4pt 넘친다.
                expect(bottomRect.minY + 16 + 10).to(beCloseTo(40 - 1.41, within: 0.01))
                expect(bottomRect.minY + 25.5).to(beCloseTo(38.09, within: 0.01))

                let center = try cellTable(
                    alignment: .center, paragraphs: [paragraph], height: 4000,
                    index: Self.overlappingIndex()
                )
                let centerRect = try XCTUnwrap(center.rows[0].cells[0].paragraphs.first?.rect)
                expect(centerRect.minY).to(beCloseTo(1.41 + (37.18 - 26) / 2, within: 0.01))

                let floor = try cellTable(
                    alignment: .top, paragraphs: [paragraph], height: 282,
                    index: Self.overlappingIndex()
                )
                expect(floor.rows[0].rowFrame.height).to(beCloseTo(28.82, within: 0.01))
            }
        }

        // MARK: 글상자

        /// 글상자도 같은 범위다 — 40pt 상자·안쪽 여백 2.83pt에서 10pt 한 줄의 상자 상단이 가운데
        /// 2.83 + 12.17, 아래 40 − 2.83 − 10 (한글 R1·R2: 베이스라인 23.52·35.72).
        func testTextboxAlignsTheLastLineBox() throws {
            let center = try textboxParagraphRect(alignment: .center)
            expect(center.minY).to(beCloseTo(15.00, within: 0.01))
            let bottom = try textboxParagraphRect(alignment: .bottom)
            expect(bottom.minY + 10).to(beCloseTo(40 - 2.83, within: 0.01))
        }

        /// 글상자 문단의 위 간격은 첫 줄 상자를 그만큼 내리고 정렬 범위에 든다 (한글 R6:
        /// 베이스라인 28.60 → 상자 20.10). 종전에는 rect 상단을 내리지 않아 위 간격이 줄 아래로
        /// 밀렸다.
        func testTextboxSpacingBeforeMovesTheFirstLineBox() throws {
            let rect = try textboxParagraphRect(alignment: .center, spacingTop: 2000)
            expect(rect.minY).to(beCloseTo(2.83 + (34.34 - 20) / 2 + 10, within: 0.01))
        }

        // MARK: 측정

        /// CT로 잰 문단의 마지막 줄 상자 아래 몫 = 줄 간격 여분 + 아래 간격.
        func testTrailingGapIsTheLastLineSpacingPlusSpacingAfter() throws {
            let measurer = HwpParagraphMeasurer(
                index: index(spacingBottom: 2000), fontResolver: .testDeterministic
            )
            let measured = measurer.measure(try HwpSynthetic.textParagraph("가"), width: 300)
            expect(measured.trailingGap).to(beCloseTo(6 + 10, within: 0.01))

            let cached = measurer.measure(
                try oneLine(), width: 300,
                options: .init(preferCachedHeight: true, addHalfSpacingBefore: true)
            )
            expect(cached.trailingGap).to(beCloseTo(6 + 10, within: 0.01))
        }
    }

    private extension HwpContainerContentExtentTests {
        struct LayoutFailure: Error {}

        func oneLine() throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph("가", segments: [(location: 0, height: 1000)])
        }

        func cellParagraphRect(
            alignment: CoreHwp.HwpListHeaderVerticalAlignment,
            paragraphs: [CoreHwp.HwpParagraph],
            spacingTop: Int32 = 0,
            spacingBottom: Int32 = 0
        ) throws -> CGRect {
            try XCTUnwrap(cellParagraphRects(
                alignment: alignment, paragraphs: paragraphs, height: 4000,
                spacingTop: spacingTop, spacingBottom: spacingBottom
            ).first)
        }

        func cellParagraphRects(
            alignment: CoreHwp.HwpListHeaderVerticalAlignment,
            paragraphs: [CoreHwp.HwpParagraph],
            height: UInt32,
            spacingTop: Int32 = 0,
            spacingBottom: Int32 = 0
        ) throws -> [CGRect] {
            try cellTable(
                alignment: alignment, paragraphs: paragraphs, height: height,
                spacingTop: spacingTop, spacingBottom: spacingBottom
            ).rows[0].cells[0].paragraphs.map(\.rect)
        }

        /// 폭 200pt·안쪽 여백 위아래 141 HWPUNIT의 1×1 표.
        func cellTable(
            alignment: CoreHwp.HwpListHeaderVerticalAlignment,
            paragraphs: [CoreHwp.HwpParagraph],
            height: UInt32,
            spacingTop: Int32 = 0,
            spacingBottom: Int32 = 0,
            lineSpacing: Int32 = 160,
            index: HwpIndex? = nil
        ) throws -> HwpTableFrame {
            var cell = HwpSynthetic.tableCell(
                row: 0, column: 0, width: 20000, height: height, paragraphs: paragraphs
            )
            cell.header.propertyInfo.verticalAlignment = alignment
            let table = CoreHwp.HwpTable(property: tableProperty(), cellArray: [cell])
            let result = HwpTableLayout(fontResolver: .testDeterministic).layout(
                table: table, availableWidth: 400,
                index: index ?? self.index(
                    spacingTop: spacingTop, spacingBottom: spacingBottom, lineSpacing: lineSpacing
                )
            )
            guard case let .success(frame) = result else {
                XCTFail("expected table layout success")
                throw LayoutFailure()
            }
            return frame
        }

        /// 200 × 40pt 글상자, 안쪽 여백 283 HWPUNIT, CT로 재는 10pt 한 줄.
        func textboxParagraphRect(
            alignment: CoreHwp.HwpListHeaderVerticalAlignment,
            spacingTop: Int32 = 0,
            lineSpacing: Int32 = 160
        ) throws -> CGRect {
            var property = Data()
            withUnsafeBytes(of: Int32(1).littleEndian) { property.append(contentsOf: $0) }
            withUnsafeBytes(of: (UInt32(alignment.rawValue) << 5).littleEndian) {
                property.append(contentsOf: $0)
            }
            let list = CoreHwp.HwpListControlList(
                header: try CoreHwp.HwpListHeader.load(property),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [try HwpSynthetic.textParagraph("가")],
                textBoxInfo: CoreHwp.HwpTextBoxListInfo(
                    leftMargin: 283, rightMargin: 283, topMargin: 283, bottomMargin: 283
                )
            )
            let component = CoreHwp.HwpShapeComponent(
                rawCtrlId: nil, ctrlId: nil, rawPayload: Data(), rawTrailing: nil,
                pictureArray: [], oleArray: [], oleRecords: [], ctrlDataRecords: [],
                textBoxListArray: [list], unknownChildren: []
            )
            var common = CoreHwp.HwpCommonCtrlProperty(commonCtrlId: .genShapeObject)
            common.width = 20000
            common.height = 4000
            let textbox = CoreHwp.HwpGenShapeObject(
                commonCtrlProperty: common, rawPayload: Data(), rawTrailing: Data(),
                shapeComponentArray: [component], ctrlDataRecords: [], unknownChildren: []
            )
            let frame = try XCTUnwrap(HwpTextboxLayout(fontResolver: .testDeterministic).layout(
                textbox: textbox, width: 200,
                index: index(spacingTop: spacingTop, lineSpacing: lineSpacing)
            ))
            expect(frame.outerFrame.height).to(beCloseTo(40, within: 0.01))
            return try XCTUnwrap(frame.paragraphs.first?.rect)
        }

        func tableProperty() -> CoreHwp.HwpTableProperty {
            CoreHwp.HwpTableProperty(
                property: 0, rowCount: 1, columnCount: 1, cellSpacing: 0,
                leftInnerMargin: 510, rightInnerMargin: 510,
                topInnerMargin: 141, bottomInnerMargin: 141,
                rowSize: [1, 0], borderFillId: 0,
                validZoneInfoSize: nil, zonePropertyArray: nil,
                rawPayload: Data(), rawTrailing: Data()
            )
        }

        /// 30pt 한 줄 + 10pt 한 줄(한 줄 끝으로 나눔) 문단 — `cached`면 한글이 저장하는 꼴의 줄
        /// 캐시(상자 3000·1000, 줄 간격 −1400·600)를 함께 단다.
        static func overlappingParagraph(cached: Bool) throws -> CoreHwp.HwpParagraph {
            var paragraph = CoreHwp.HwpParagraph()
            var text = CoreHwp.HwpParaText()
            text.charArray = [
                CoreHwp.HwpChar(type: .char, value: 0xAC00),
                CoreHwp.HwpChar(type: .char, value: 10),
                CoreHwp.HwpChar(type: .char, value: 0xB098),
            ]
            paragraph.paraText = text
            var shapes = CoreHwp.HwpParaCharShape()
            shapes.startingIndex = [0, 2]
            shapes.shapeId = [0, 1]
            paragraph.paraCharShape = shapes
            paragraph.paraLineSeg.paraLineSegInternalArray = []
            guard cached else { return paragraph }
            var payload = Data()
            for (location, height, spacing) in [
                (Int32(0), Int32(3000), Int32(-1400)), (Int32(1600), Int32(1000), Int32(600)),
            ] {
                withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: location.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: height.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: (height * 85 / 100).littleEndian) {
                    payload.append(contentsOf: $0)
                }
                withUnsafeBytes(of: spacing.littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: Int32(19716).littleEndian) { payload.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt32(393_216).littleEndian) { payload.append(contentsOf: $0) }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            return paragraph
        }

        /// 글자 모양 0 = 30pt·1 = 10pt, 문단 모양 = 고정 줄 간격 16pt (표 46 종류 1).
        static func overlappingIndex() -> HwpIndex {
            var paraShape = CoreHwp.HwpParaShape(
                property1: 1, marginLeft: 0, lineSpacing: 3200, tabDefId: 0, lineSpacing2: 3200
            )
            paraShape.property3 = 1
            func charShape(_ size: Int32) -> CoreHwp.HwpCharShape {
                CoreHwp.HwpCharShape(
                    faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0],
                    baseSize: size, faceColor: CoreHwp.HwpColor()
                )
            }
            return HwpIndex(
                charShapes: [0: charShape(3000), 1: charShape(1000)],
                paraShapes: [0: paraShape],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        /// 줄 간격 비율(기본 160%) — 문단 위/아래 간격은 표 43 여백 계열의 1/2 단위
        /// (2000 → 10pt).
        func index(
            spacingTop: Int32 = 0, spacingBottom: Int32 = 0, lineSpacing: Int32 = 160
        ) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0,
                    marginLeft: 0,
                    paragraphSpacingTop: spacingTop,
                    paragraphSpacingBottom: spacingBottom,
                    lineSpacing: lineSpacing,
                    tabDefId: 0,
                    lineSpacing2: UInt32(lineSpacing)
                )],
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
    }
#endif
