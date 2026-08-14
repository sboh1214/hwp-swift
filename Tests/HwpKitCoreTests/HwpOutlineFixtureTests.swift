@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개요·책갈피 수집의 **실측 핀** (#77).
    ///
    /// 저장소 픽스처 33종 중 개요 문단을 가진 것은
    /// `legacy-common-control-property`(헌법주석) 하나뿐이고 (나머지는 0개,
    /// 암호·DRM 4종은 FileHeader에서 거부), 책갈피를 가진 것은 `bookmark`
    /// 하나뿐이다. 그 둘이 두 경로의 오라클을 겸한다.
    ///
    /// 개요 쪽은 **조판 없이** 수집기를 직접 몬다 — 1,030쪽을 다시 배치하지 않고도
    /// 수준 판정·제목 정규화·개수를 전부 태울 수 있고 (쪽 귀속은
    /// `HwpOutlineCollectorTests`가 합성 문서로 본다), 스위트가 1초 안에 끝난다.
    final class HwpOutlineFixtureTests: XCTestCase {
        private func fixture(_ id: String) throws -> CoreHwp.HwpFile {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/\(id)/document.hwp")
            return try CoreHwp.HwpFile(fromPath: url.path)
        }

        /// 조판을 건너뛰고 수집기만 몬다 — 쪽은 전부 1로 둔다.
        private func collectHeadings(from file: CoreHwp.HwpFile) -> [HwpOutlineItem] {
            var collector = HwpOutlineCollector(index: HwpIndex(from: file))
            for section in file.displaySectionArray {
                for paragraph in section.paragraph {
                    collector.collect(
                        from: paragraph,
                        headingPage: 1,
                        bookmarkPage: 1,
                        maximumPage: 1,
                        childParagraphs: { _ in [] }
                    )
                }
            }
            return collector.items
        }

        func testLegacyFixtureOutlineMatchesMeasuredDistribution() throws {
            let items = collectHeadings(from: try fixture("legacy-common-control-property"))

            expect(items.count) == 1944
            expect(items.allSatisfy { $0.kind == .heading }) == true
            // 1-기반 수준 = 저장 비트 + 1. 분포는 스타일 이름 분포와 개수까지 같다
            // (`ParaShapePropertyInfoTests`가 파서 층에서 그 대응을 잡는다).
            var levelCounts: [Int: Int] = [:]
            for item in items {
                levelCounts[try XCTUnwrap(item.level), default: 0] += 1
            }
            expect(levelCounts) == [1: 280, 2: 512, 3: 486, 4: 301, 5: 244, 6: 100, 7: 21]
            // 제목은 전부 비어 있지 않고 상한 안이다.
            expect(items.contains { $0.title.isEmpty }) == false
            expect(items.allSatisfy { $0.title.count <= HwpOutlineItem.titleCharacterLimit })
                == true
            expect(items.first?.title) == "대한민국헌법 제정의 유래"
            expect(items.map(\.ordinal)) == Array(0 ..< items.count)
        }

        /// 개요가 없는 문서에서는 목록도 비어 있다 — 사이드바를 숨기는 근거.
        func testFixturesWithoutOutlineProduceNoHeadings() throws {
            for id in ["noori", "memo", "header-footer", "footnote-endnote"] {
                let items = collectHeadings(from: try fixture(id))
                expect(items).to(beEmpty(), description: "\(id)에 개요 항목이 생겼다")
            }
        }

        /// 책갈피는 실제 조판 파이프라인을 통과시켜 본다 — 이름이 뷰어 로드
        /// (`.viewer`, `preserveRawPayload = false`)에서도 살아 있어야 한다.
        func testBookmarkFixtureProducesNavigableAnchorThroughPagination() async throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/bookmark/document.hwp")
            let file = try CoreHwp.HwpFile(fromPath: url.path, options: .viewer)
            let paginator = HwpPaginator(
                sections: file.displaySectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let unsupported = await paginator.unsupportedElements()

            expect(outline.map(\.title)) == ["CoreHwpBookmark"]
            expect(outline.first?.kind) == .bookmark
            expect(outline.first?.level).to(beNil())
            expect(outline.first?.pageNumber) == 1
            // 책갈피는 이제 소비되는 컨트롤이라 미지원으로 보고하지 않는다 (#77).
            expect(unsupported.map(\.hint)).toNot(contain("알 수 없음: bookmark"))
        }
    }
#endif
