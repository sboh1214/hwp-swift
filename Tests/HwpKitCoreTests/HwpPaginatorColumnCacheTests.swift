@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 한글 라인 캐시 기반 단 배분 (loc 리셋 = 단 경계)과 밴드 간 줄 간격,
    /// 글자처럼 취급 표의 인라인 앵커 배치 테스트 (Column/noori PrvImage 실측 동작).
    final class HwpPaginatorColumnCacheTests: XCTestCase {
        private func firstPage(
            of section: CoreHwp.HwpSection
        ) async throws -> HwpPage? {
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            return try await paginator.page(at: 0)
        }

        /// 20000×10000 HWPUNIT 단일 셀 표 (컨테이너 개체 테스트 공용 픽스처)
        private func singleCellTable(
            _ cellParagraph: CoreHwp.HwpParagraph
        ) -> CoreHwp.HwpTable {
            var table = HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [10000], cellParagraphs: [[[cellParagraph]]]
            )
            table.commonCtrlProperty.width = 20000
            table.commonCtrlProperty.height = 10000
            return table
        }

        /// 표 하나를 본문에 실은 첫 페이지와 그 표 payload
        private func tableFrame(
            hosting table: CoreHwp.HwpTable
        ) async throws -> (page: HwpPage, frame: HwpTableFrame)? {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "표 ", suffix: "")
            host.ctrlHeaderArray = [.table(table)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            guard let page = try await firstPage(of: section),
                  let block = page.blocks.first(where: { $0.kind == .table }),
                  case let .table(frame) = block.payload
            else { return nil }
            return (page, frame)
        }

        /// 비등폭 2단에서 캐시 run 경계 (textStartingIndex)대로 텍스트가
        /// 좁은 단/넓은 단에 배분된다 — 라인 수 균등 분배가 아니다.
        func testCachedRunsDistributeTextByCharPosition() async throws {
            let words = (0 ..< 18).map { "word\($0)" }
            let text = words.joined(separator: " ") // 125자
            let textCount = UInt32(text.utf16.count)
            // 좁은 단 (약 1/3 폭)에 앞 1/3, 넓은 단에 나머지 (Column p3 패턴)
            let boundary = textCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ])
            // Column 픽스처 패턴: 단 정의가 해당 문단에 부착 → 문단 시작 = 새 밴드
            paragraph.ctrlHeaderArray = [.column(HwpSynthetic.column(
                count: 2,
                widths: [10339, 20682],
                gaps: [1747, 0]
            ))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            let textBlocks = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(textBlocks.count) == 2

            guard textBlocks.count == 2,
                  let leftText = textBlocks[0].attributedString?.string,
                  let rightText = textBlocks[1].attributedString?.string
            else { return }
            // 두 단이 서로 다른 프레임에서 시작하고 원문을 나눠 담는다
            expect(textBlocks[1].frame.minX) > textBlocks[0].frame.maxX - 1
            expect(leftText + rightText) == text
            // 경계는 캐시 비례 위치 (1/3) 근처의 CT 라인 시작으로 스냅된다
            let leftCount = Double(leftText.utf16.count)
            expect(leftCount) > Double(textCount) / 6
            expect(leftCount) < Double(textCount) * 2 / 3
            // 각 단 블록 높이 = run의 캐시 높이 (loc 2552 + 1500 + 600 = 46.52pt)
            expect(textBlocks[0].frame.height).to(beCloseTo(46.52, within: 0.5))
            expect(textBlocks[1].frame.height).to(beCloseTo(46.52, within: 0.5))
            // 같은 밴드: 두 단의 시작 y가 같다
            expect(textBlocks[0].frame.minY).to(beCloseTo(textBlocks[1].frame.minY, within: 0.5))
        }

        /// 단 정의로 밴드를 닫으면 다음 밴드는 마지막 줄의 줄 간격만큼 띄운 뒤
        /// 시작한다 (Column PrvImage 실측: 밴드 간 시작 간격 = 줄 전진량 + 줄 간격).
        func testColumnBandGapAddsTrailingLineSpacing() async throws {
            // 캐시 두 줄 (h 1000 + sp 600 → 블록 32pt), 그다음 밴드 시작
            var first = try HwpSynthetic.lineSegParagraph(
                "첫 밴드 문단",
                segments: [(location: 0, height: 1000), (location: 1600, height: 1000)]
            )
            first.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            var second = try HwpSynthetic.lineSegParagraph(
                "둘째 밴드 문단",
                segments: [(location: 0, height: 1000)]
            )
            second.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [first, second]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            let blocks = page.blocks
                .filter { $0.attributedString?.string.contains("밴드 문단") == true }
                .sorted { $0.frame.minY < $1.frame.minY }
            expect(blocks.count) == 2
            guard blocks.count == 2 else { return }
            // 32pt (캐시 높이) + 6pt (마지막 줄 간격 600)
            expect(blocks[1].frame.minY - blocks[0].frame.minY)
                .to(beCloseTo(38, within: 0.5))
        }

        /// 글자처럼 취급 표는 FFFC 앵커 줄 위치에 배치되고 흐름 높이를 추가로
        /// 소비하지 않는다 (noori 보도자료 표 실측: 캐시 줄 높이 = 표 높이).
        func testTreatAsCharTableAnchorsToItsLine() async throws {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "앞 ", suffix: " 뒤")
            var table = singleCellTable(try HwpSynthetic.textParagraph("셀"))
            table.commonCtrlProperty.instanceId = 7
            var info = CoreHwp.HwpCommonCtrlPropertyInfo()
            info.treatAsChar = true
            // 한글은 고정 크기 개체에 크기 기준 '절대값'을 저장한다 — 기본값
            // (.paper)이면 width/height가 퍼센트 (10000 = 100%)로 해석된다.
            info.widthRelativeTo = .absolute
            info.heightRelativeTo = .absolute
            table.commonCtrlProperty.propertyInfo = info
            host.ctrlHeaderArray = [.table(table)]

            let follower = try HwpSynthetic.textParagraph("다음 문단")
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host, follower]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            guard let hostBlock = page.blocks.first(where: {
                $0.kind == .text && $0.attributedString?.string.contains("앞") == true
            }) else {
                fail("호스트 문단 블록이 없다")
                return
            }
            guard let tableBlock = page.blocks.first(where: {
                $0.kind == .table && $0.source?.controlInstanceId == 7
            }) else {
                fail("인라인 표 블록이 없다")
                return
            }
            guard let followerBlock = page.blocks.first(where: {
                $0.attributedString?.string.contains("다음 문단") == true
            }) else {
                fail("후속 문단 블록이 없다")
                return
            }

            // 표(100pt)가 줄에서 가장 크므로 표 위 == 앵커 줄 위 == 블록 위
            expect(tableBlock.frame.minY).to(beCloseTo(hostBlock.frame.minY, within: 1))
            expect(tableBlock.frame.height).to(beCloseTo(100, within: 1))
            // 줄 공간은 run delegate가 예약: 호스트 블록이 표 높이를 포함하고,
            // 후속 문단은 표 높이를 이중 소비하지 않고 바로 아래에서 시작한다
            expect(hostBlock.frame.height) >= 100
            expect(followerBlock.frame.minY - hostBlock.frame.minY) < 150
        }

        /// 셀 안 그림은 셀 콘텐츠 (HwpCellImage)로 배치되고 페이지 흐름 블록으로
        /// 방출되지 않는다 — 큰 그림이 페이지를 밀어내지 않는다 (noori 실측 3쪽).
        func testCellPictureRendersInsideCellWithoutFlowBlock() async throws {
            var cellParagraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            cellParagraph.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlinePictureObject(
                width: 20000,
                height: 5000,
                binItemId: 5,
                instanceId: 9
            ))]
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "표 ", suffix: "")
            host.ctrlHeaderArray = [.table(singleCellTable(cellParagraph))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )

            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var pages: [HwpPage] = []
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                pages.append(page)
                pageIndex += 1
            }

            // 그림이 흐름을 소비하지 않으므로 한 페이지로 끝난다
            expect(pages.count) == 1
            guard let tableBlock = pages.first?.blocks.first(where: { $0.kind == .table }),
                  case let .table(frame) = tableBlock.payload
            else {
                fail("표 블록이 없다")
                return
            }
            let images = frame.rows.flatMap(\.cells).flatMap(\.images)
            expect(images.count) == 1
            expect(images.first?.binItemId) == 5
            // 별도 이미지 흐름 블록은 방출되지 않는다
            let imageBlocks = pages.flatMap(\.blocks).filter { $0.kind == .image }
            expect(imageBlocks).to(beEmpty())
        }

        /// 셀 안 글상자는 셀 콘텐츠 (HwpCellTextbox)로 배치되고 페이지 흐름
        /// 블록으로 방출되지 않는다 (R29 #1).
        func testCellTextboxRendersInsideCellWithoutFlowBlock() async throws {
            var cellParagraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            cellParagraph.ctrlHeaderArray = try [.genShapeObject(
                HwpSynthetic.inlineTextboxObject(
                    width: 15000, height: 5000, text: "상자", instanceId: 11
                )
            )]

            guard let (page, frame) = try await tableFrame(
                hosting: singleCellTable(cellParagraph)
            ) else {
                fail("표 블록이 없다")
                return
            }
            let textboxes = frame.rows.flatMap(\.cells).flatMap(\.textboxes)
            expect(textboxes.count) == 1
            expect(textboxes.first?.controlInstanceId) == 11
            expect(
                textboxes.first?.textbox.paragraphs.first?.attributedString.string
            ).to(contain("상자"))
            // 별도 글상자 흐름 블록은 방출되지 않는다
            let textboxBlocks = page.blocks.filter { $0.kind == .textbox }
            expect(textboxBlocks).to(beEmpty())
        }

        /// 글상자 문단 안 그림은 글상자 콘텐츠 (frame.images)로 배치되고
        /// 별도 흐름 블록으로 방출되지 않는다 (R29 #1).
        func testTextboxPictureRendersInsideTextboxBlock() async throws {
            var boxParagraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            boxParagraph.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlinePictureObject(
                width: 10000, height: 4000, binItemId: 7, instanceId: 12
            ))]
            var textbox = try HwpSynthetic.inlineTextboxObject(
                width: 20000, height: 8000, text: "", instanceId: 13
            )
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [boxParagraph]
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "글 ", suffix: "")
            host.ctrlHeaderArray = [.genShapeObject(textbox)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }

            guard let textboxBlock = page.blocks.first(where: { $0.kind == .textbox }),
                  case let .textbox(frame) = textboxBlock.payload
            else {
                fail("글상자 블록이 없다")
                return
            }
            expect(frame.images.count) == 1
            expect(frame.images.first?.binItemId) == 7
            // 그림이 별도 흐름 블록으로 중복 방출되지 않는다
            let imageBlocks = page.blocks.filter { $0.kind == .image }
            expect(imageBlocks).to(beEmpty())
        }

        /// 떠 있는 (treatAsChar 아님) 셀 그림은 마커 위치가 아니라 저작
        /// 오프셋 기준으로 배치된다 (R30 #1).
        func testFloatingCellPictureHonorsAuthoredOffset() async throws {
            var cellParagraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            var picture = HwpSynthetic.inlinePictureObject(
                width: 5000, height: 3000, binItemId: 5, instanceId: 9
            )
            picture.commonCtrlProperty.propertyInfo.treatAsChar = false
            picture.commonCtrlProperty.horizontalOffset = 2000
            picture.commonCtrlProperty.verticalOffset = 1000
            cellParagraph.ctrlHeaderArray = [.genShapeObject(picture)]

            guard let (_, frame) = try await tableFrame(
                hosting: singleCellTable(cellParagraph)
            ), let image = frame.rows.flatMap(\.cells).flatMap(\.images).first
            else {
                fail("셀 그림이 없다")
                return
            }
            // 2000/1000 HWPUNIT = 20/10pt — 문단 rect 원점 (0,0) + 오프셋
            expect(image.rect.minX).to(beCloseTo(20, within: 1))
            expect(image.rect.minY).to(beCloseTo(10, within: 1))
        }

        /// commonCtrlProperty가 nil인 레거시 도형 컨트롤의 글상자도 기본
        /// property로 빌드되어 셀 콘텐츠로 렌더된다 — 억제와 수집의 일치 (R30 #4).
        func testNilPropertyCellTextboxStillRenders() async throws {
            let box = try HwpSynthetic.inlineTextboxObject(
                width: 15000, height: 5000, text: "레거시", instanceId: 0
            )
            let legacy = CoreHwp.HwpShapeControl(
                ctrlId: .rectangle,
                commonCtrlProperty: nil,
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: box.shapeComponentArray,
                eqEditArray: [],
                eqEditRecords: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            var cellParagraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            cellParagraph.ctrlHeaderArray = [.rectangle(legacy)]

            guard let (_, frame) = try await tableFrame(
                hosting: singleCellTable(cellParagraph)
            ) else {
                fail("표 블록이 없다")
                return
            }
            let textboxes = frame.rows.flatMap(\.cells).flatMap(\.textboxes)
            expect(textboxes.count) == 1
            expect(
                textboxes.first?.textbox.paragraphs.first?.attributedString.string
            ).to(contain("레거시"))
        }
    }
#endif
