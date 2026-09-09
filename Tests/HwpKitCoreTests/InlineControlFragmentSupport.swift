import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// `HwpInlineControlFragmentTests`·`HwpInlineControlFragmentColumnTests` 공용 입력·조회 (#164).
    enum InlineControlFragmentSupport {
        /// 높이는 HWPUNIT (기본 1000 = 10pt).
        static func inlineTable(
            instanceId: UInt32,
            height: UInt32 = 1000,
            cell: CoreHwp.HwpParagraph? = nil
        ) throws -> CoreHwp.HwpCtrlId {
            var table = HwpSynthetic.table(
                cellWidth: 6000, rowHeights: [height],
                cellParagraphs: [[[try cell ?? HwpSynthetic.textParagraph("셀")]]]
            )
            table.commonCtrlProperty.width = 6000
            table.commonCtrlProperty.height = height
            table.commonCtrlProperty.instanceId = instanceId
            var info = CoreHwp.HwpCommonCtrlPropertyInfo()
            info.treatAsChar = true
            // 한글은 고정 크기 개체에 크기 기준 '절대값'을 저장한다 — 기본값(.paper)이면
            // width/height가 퍼센트로 해석된다.
            info.widthRelativeToRawValue = 4
            info.widthRelativeTo = .absolute
            info.heightRelativeToRawValue = 2
            info.heightRelativeTo = .absolute
            table.commonCtrlProperty.propertyInfo = info
            return .table(table)
        }

        /// OLE 컴포넌트를 품은 도형 — `HwpParagraphObjectCollector.collectible`이
        /// `oleArray` 때문에 false라 컨테이너가 안 그리고 문단 끝 흐름 폴백으로 나간다.
        /// 진단은 "OLE"로 잡힌다.
        static func oleShape(instanceId: UInt32) -> CoreHwp.HwpCtrlId {
            var object = HwpSynthetic.inlineShapeObject(
                width: 3000, height: 500, instanceId: instanceId
            )
            var component = object.shapeComponentArray[0]
            component.oleArray = [CoreHwp.HwpShapeComponentOLE(
                rawPayload: Data(), binaryDataId: nil, rawTrailing: nil, unknownChildren: []
            )]
            object.shapeComponentArray[0] = component
            return .genShapeObject(object)
        }

        static func objectBlocks(on page: HwpPage, instanceId: UInt32) -> [AnyHwpBlock] {
            page.blocks.filter { $0.source?.controlInstanceId == instanceId }
        }

        /// 그 쪽에 놓인 본문 문단(구역 첫 문단 다음, 서수 1)의 텍스트 블록 — 문단 조각.
        /// 구역 첫 문단도 구역·단 정의 마커(U+FFFC)를 품으므로 마커로는 가르지 못한다.
        static func hostFragment(on page: HwpPage) -> AnyHwpBlock? {
            page.blocks.first {
                $0.kind == .text && $0.source?.sectionIndex == 0 && $0.source?.paragraphIndex == 1
            }
        }

        /// 렌더러가 그리는 대로 조판한 마커(U+FFFC, `controlIndex`)의 x와 그 줄의 baseline y
        /// — 블록 프레임 좌표. 줄 안 개체의 앵커가 그려진 글자·줄과 맞는지 대조하는 오라클이다.
        /// 양쪽 정렬 줄은 렌더러가 빈칸에만 남는 폭을 배분해 다시 조판하므로 x는 측정과
        /// 몇 pt 갈릴 수 있다 — 그 축은 이 테스트의 몫이 아니다 (AGENTS.md "양쪽 정렬").
        static func drawnMarker(
            in attributedString: NSAttributedString,
            origin: CGPoint,
            lineWidth: CGFloat,
            controlIndex: Int
        ) -> (x: CGFloat, baselineY: CGFloat)? {
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            for line in drawn {
                guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { continue }
                for run in runs {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard let number = attributes[HwpAttributedStringKey.controlIndex] as? NSNumber,
                          number.intValue == controlIndex
                    else { continue }
                    let location = CTRunGetStringRange(run).location
                    let offset = CTLineGetOffsetForStringIndex(line.line, location, nil)
                    return (line.baselineOrigin.x + offset, line.baselineOrigin.y)
                }
            }
            return nil
        }

        /// 마커(U+FFFC, `controlIndex`)가 줄에서 차지하는 예약 폭 — run delegate가 낸다.
        /// 그려지는 개체 블록의 폭과 같아야 개체가 뒤 글자를 덮지 않는다.
        static func reservedMarkerWidth(
            in attributedString: NSAttributedString,
            controlIndex: Int
        ) -> CGFloat? {
            var reserved: CGFloat?
            attributedString.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, range, stop in
                guard (value as? NSNumber)?.intValue == controlIndex else { return }
                let line = CTLineCreateWithAttributedString(
                    attributedString.attributedSubstring(from: range)
                )
                reserved = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                stop.pointee = true
            }
            return reserved
        }

        /// 묶음 개체(`.genShapeObject`)가 아닌 **도형 컨트롤**(`HwpShapeControl`) 형태의
        /// 글자처럼 취급 개체 — 판정(`isTreatAsChar`)과 방출(`appendInlineControlBlock`)
        /// 모두 묶음 개체와 다른 갈래를 탄다.
        static func inlineRectangle(instanceId: UInt32) -> CoreHwp.HwpCtrlId {
            let object = HwpSynthetic.inlineShapeObject(
                width: 6000, height: 1000, instanceId: instanceId
            )
            return .rectangle(CoreHwp.HwpShapeControl(
                ctrlId: .rectangle,
                commonCtrlProperty: object.commonCtrlProperty,
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: object.shapeComponentArray,
                eqEditArray: [],
                eqEditRecords: [],
                ctrlDataRecords: [],
                unknownChildren: []
            ))
        }

        /// 오른쪽 정렬 문단 모양 — 속성1 bit 2-4 = 2.
        static func rightAlignedParaShape() -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                hwpxProperty1: 2 << 2, marginLeft: 0, marginRight: 0, indent: 0,
                paragraphSpacingTop: 0, paragraphSpacingBottom: 0, lineSpacing: 160,
                tabDefId: 0, numberingOrBulletId: 0, borderFillId: 0,
                borderSpacingLeft: 0, borderSpacingRight: 0, borderSpacingTop: 0,
                borderSpacingBottom: 0, property3: 0, lineSpacing2: 160
            )
        }

        static func pages(of paginator: HwpPaginator) async throws -> [HwpPage] {
            var pages: [HwpPage] = []
            var pageIndex = 0
            while let page = try await paginator.page(at: pageIndex) {
                pages.append(page)
                pageIndex += 1
            }
            return pages
        }

        static func splitHost(
            controls: [CoreHwp.HwpCtrlId]
        ) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithControlMarkers(
                lines: [
                    (characters: 5, marker: true),
                    (characters: 5, marker: false),
                    (characters: 5, marker: true),
                ],
                segments: [
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 14),
                    // location이 줄어드는 지점이 한글의 페이지 절단점 (run 1)
                    (location: 2720, height: 1500, textStart: 28),
                ],
                markerCode: 11
            )
            host.ctrlHeaderArray = controls
            return host
        }

        /// 절대 캐시 문서 — 본문 뒤에 캐시 문단 둘을 더해 절대 모드 감지(첫 loc > 0인
        /// 캐시 문단 다수)를 만족시킨다. 둘째 쪽의 뒤 문단은 run 1 바로 아래(4820)다.
        static func absolutePaginator(
            host: CoreHwp.HwpParagraph
        ) throws -> HwpPaginator {
            let tail = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "뒤 문단 \(index)",
                    segments: [(location: Int32(4820 + index * 2100), height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host] + tail
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }
    }
#endif
