@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 번호 위치 (pgNumPos, 표 147/148)와 쪽 감추기 (pghd, 표 145) 렌더 검증
    final class HwpPaginatorPageNumberTests: XCTestCase {
        func testPageNumberEmittedOnEveryPage() async throws {
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            for pageIndex in 0 ..< totalPages {
                let page = try await paginator.page(at: pageIndex)
                expect(self.pageNumberTexts(of: page)).to(
                    contain("- \(pageIndex + 1) -"),
                    description: "page \(pageIndex + 1)에 쪽 번호가 없다"
                )
            }
        }

        func testPageNumberUsesNumberFormatAndDecorations() async throws {
            // 로마 소문자 (표 134 코드 3) + 앞/뒤 장식 '-'
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(
                        numberFormat: 3,
                        displayPosition: 5,
                        headDecoration: "-",
                        tailDecoration: "-"
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)

            expect(self.pageNumberTexts(of: firstPage)).to(contain("-i-"))
            expect(self.pageNumberTexts(of: secondPage)).to(contain("-ii-"))
        }

        func testPageNumberWithoutSideCharDrawsBareNumber() async throws {
            // 줄표 필드(표 147 4번째 WCHAR)가 0이면 번호만 — noori 실측, 한글.app "1" (#138)
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(
                        numberFormat: 0,
                        displayPosition: 5,
                        sideChar: nil
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)

            expect(self.pageNumberTexts(of: firstPage)) == ["1"]
            expect(self.pageNumberTexts(of: secondPage)) == ["2"]
        }

        func testPageNumberDecorationsTakePrecedenceOverSideChar() async throws {
            // 앞/뒤 장식 문자가 있으면 줄표 필드 값과 무관하게 장식만 붙는다
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(
                        numberFormat: 0,
                        displayPosition: 5,
                        headDecoration: "[",
                        tailDecoration: "]",
                        sideChar: "-"
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            expect(self.pageNumberTexts(of: firstPage)) == ["[1]"]
        }

        func testPageHideSuppressesPageNumberOnControlPage() async throws {
            // 첫 문단의 pghd (0x20)는 1페이지 쪽 번호만 감춘다 (헌법주석 표지 구조)
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                    HwpSynthetic.pageHideControl(mask: 0x20),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            let firstPage = try await paginator.page(at: 0)
            expect(self.pageNumberTexts(of: firstPage)).to(
                beEmpty(),
                description: "감춘 페이지에 쪽 번호가 있다"
            )
            let secondPage = try await paginator.page(at: 1)
            expect(self.pageNumberTexts(of: secondPage)).to(contain("- 2 -"))
        }

        func testPageHideSuppressesHeaderAndFooterOnControlPage() async throws {
            let header = HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: [try HwpSynthetic.textParagraph("반복 머리말")]
            )
            let footer = HwpSynthetic.listControl(
                ctrlId: .footer,
                paragraphs: [try HwpSynthetic.textParagraph("반복 꼬리말")]
            )
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .header(header),
                    .footer(footer),
                    HwpSynthetic.pageHideControl(mask: 0x03),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            let firstTexts = try await allTexts(of: paginator, pageIndex: 0)
            expect(firstTexts.contains { $0.contains("반복 머리말") }).to(beFalse())
            expect(firstTexts.contains { $0.contains("반복 꼬리말") }).to(beFalse())

            let secondTexts = try await allTexts(of: paginator, pageIndex: 1)
            expect(secondTexts.contains { $0.contains("반복 머리말") }).to(beTrue())
            expect(secondTexts.contains { $0.contains("반복 꼬리말") }).to(beTrue())
        }

        func testNewPageNumberResetsLogicalNumber() async throws {
            // nwno (kind 0 쪽, number 9): 컨트롤이 있는 페이지부터 9로 표시
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                ],
                leadingBodyParagraphs: [
                    HwpSynthetic.markerParagraph(
                        control: HwpSynthetic.newNumberControl(kind: 0, number: 9)
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)

            expect(self.pageNumberTexts(of: firstPage)).to(contain("- 9 -"))
            expect(self.pageNumberTexts(of: secondPage)).to(contain("- 10 -"))
        }

        // MARK: 구역 시작 종류 (표 130 bits 20-21, #185)

        /// 홀수·짝수 시작은 새 구역 첫 쪽의 번호만 건너뛰고 빈 쪽을 끼우지 않는다 —
        /// 한글 12.30이 `section-page-number-skip` 쌍을 PDF로 내보낸 7쪽의 번호
        /// 1·3·4·6·7·9·10과 같다 (이어서 → 홀수(2를 건너뜀) → 짝수(이미 짝수) →
        /// 짝수(5를 건너뜀) → 홀수(이미 홀수) → 사용자 9 → 이어서).
        func testSectionStartParitySkipsOnlyMismatchedPageNumbers() async throws {
            let paginator = try makeSectionedPaginator(sectionDefs: [
                HwpSynthetic.sectionDef(),
                HwpSynthetic.sectionDef(pageStartsOn: .odd),
                HwpSynthetic.sectionDef(pageStartsOn: .even),
                HwpSynthetic.sectionDef(pageStartsOn: .even),
                HwpSynthetic.sectionDef(pageStartsOn: .odd),
                HwpSynthetic.sectionDef(pageStartNumber: 9),
                HwpSynthetic.sectionDef(),
            ])

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 7
            let paginatorTexts = try await pageNumberTexts(of: paginator)
            expect(paginatorTexts) == [
                ["- 1 -"], ["- 3 -"], ["- 4 -"], ["- 6 -"], ["- 7 -"], ["- 9 -"], ["- 10 -"],
            ]
        }

        /// 문서 첫 구역도 같은 규칙이다 — 짝수 시작이면 첫 쪽이 2, 홀수 시작이면 1 그대로
        /// (한글 12.30 실측: `probe-first-even` 2·3, `probe-first-odd` 1·2).
        func testFirstSectionEvenStartNumbersTheFirstPageTwo() async throws {
            let even = try makeSectionedPaginator(sectionDefs: [
                HwpSynthetic.sectionDef(pageStartsOn: .even),
                HwpSynthetic.sectionDef(),
            ])
            let evenTexts = try await pageNumberTexts(of: even)
            expect(evenTexts) == [["- 2 -"], ["- 3 -"]]

            let odd = try makeSectionedPaginator(sectionDefs: [
                HwpSynthetic.sectionDef(pageStartsOn: .odd),
                HwpSynthetic.sectionDef(),
            ])
            let oddTexts = try await pageNumberTexts(of: odd)
            expect(oddTexts) == [["- 1 -"], ["- 2 -"]]
        }

        /// 사용자 지정 시작 번호가 있으면 홀수·짝수 종류는 보지 않는다 — 한글 12.30은
        /// `ODD` + `page="4"`를 4로, `EVEN` + `page="7"`을 7로 찍고 다음 구역은 8이다
        /// (`probe-parity-custom`). 종류만 보면 5·8·9가 된다.
        func testUserPageStartNumberIgnoresSectionStartParity() async throws {
            let paginator = try makeSectionedPaginator(sectionDefs: [
                HwpSynthetic.sectionDef(),
                HwpSynthetic.sectionDef(pageStartsOn: .odd, pageStartNumber: 4),
                HwpSynthetic.sectionDef(pageStartsOn: .even, pageStartNumber: 7),
                HwpSynthetic.sectionDef(),
            ])
            let paginatorTexts = try await pageNumberTexts(of: paginator)
            expect(paginatorTexts) == [
                ["- 1 -"], ["- 4 -"], ["- 7 -"], ["- 8 -"],
            ]
        }

        /// 새 번호 지정(nwno)은 구역 시작 종류보다 늦게 적용된다 — 홀수 시작 구역의 첫
        /// 문단에 쪽 번호 20을 지정하면 그 쪽은 20이다 (컨트롤은 문단 배치 때 확정되므로
        /// 구역 진입 때 건너뛴 값을 덮는다). 짝/홀 판정용 머리말도 같은 번호를 본다.
        func testNewPageNumberInSectionFirstParagraphOverridesParity() async throws {
            let paginator = try makeSectionedPaginator(
                sectionDefs: [
                    HwpSynthetic.sectionDef(),
                    HwpSynthetic.sectionDef(pageStartsOn: .odd),
                ],
                leadingBodyParagraphsBySection: [
                    1: [HwpSynthetic.markerParagraph(
                        control: HwpSynthetic.newNumberControl(kind: 0, number: 20)
                    )],
                ]
            )
            let paginatorTexts = try await pageNumberTexts(of: paginator)
            expect(paginatorTexts) == [["- 1 -"], ["- 20 -"]]
        }

        /// 다중 쪽 구역 뒤의 홀짝 판정은 그 구역의 **마지막** 쪽 번호에서 이어진다 — 앞
        /// 구역이 짝수 쪽에서 끝나면 홀수 시작은 건너뛰지 않고 짝수 시작이 1을 건너뛴다.
        /// 어느 쪽이든 물리 쪽은 늘지 않고 그 뒤 번호는 연속이다.
        func testSectionStartParityContinuesFromTheLastPageOfThePreviousSection() async throws {
            let alone = try makeSectionedPaginator(
                sectionDefs: [HwpSynthetic.sectionDef(pageHeight: 30000)],
                bodyParagraphCount: 40
            )
            let firstSectionPages = await alone.totalPages()
            expect(firstSectionPages) >= 2
            let continuing = firstSectionPages + 1
            let cases: [(CoreHwp.HwpSectionPageStartsOn, Int)] = [
                (.odd, continuing.isMultiple(of: 2) ? continuing + 1 : continuing),
                (.even, continuing.isMultiple(of: 2) ? continuing : continuing + 1),
            ]
            for (kind, expected) in cases {
                let paginator = try makeSectionedPaginator(
                    sectionDefs: [
                        HwpSynthetic.sectionDef(pageHeight: 30000),
                        HwpSynthetic.sectionDef(pageHeight: 30000, pageStartsOn: kind),
                    ],
                    bodyParagraphCount: 40
                )
                let texts = try await pageNumberTexts(of: paginator)
                expect(texts.count) > firstSectionPages
                expect(texts[firstSectionPages - 1]) == ["- \(firstSectionPages) -"]
                let tail = Array(texts[firstSectionPages...])
                expect(tail).to(
                    equal((0 ..< tail.count).map { ["- \(expected + $0) -"] }),
                    description: "\(kind) 시작 구역의 쪽 번호가 \(expected)부터 연속이어야 한다"
                )
            }
        }
    }

    private extension HwpPaginatorPageNumberTests {
        /// 구역마다 구역 정의 하나와 본문 문단 `bodyParagraphCount`개를 둔 다중 구역 문서.
        /// 쪽 번호 위치 컨트롤은 첫 구역에만 두고(구역을 넘어도 유지 — 한글의 동작), 문단 수가
        /// 적어 기본 쪽 크기에서는 구역마다 1쪽이다. `leadingBodyParagraphsBySection`은 그
        /// 구역의 본문 앞에 끼울 문단(새 번호 지정 마커 등)이다.
        func makeSectionedPaginator(
            sectionDefs: [CoreHwp.HwpSectionDef],
            leadingBodyParagraphsBySection: [Int: [CoreHwp.HwpParagraph]] = [:],
            bodyParagraphCount: Int = 2
        ) throws -> HwpPaginator {
            let sections = try sectionDefs.enumerated().map { offset, sectionDef in
                var controls: [CoreHwp.HwpCtrlId] = [.section(sectionDef)]
                if offset == 0 {
                    controls.append(
                        HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5)
                    )
                }
                let body = try (0 ..< bodyParagraphCount).map {
                    try HwpSynthetic.textParagraph("구역 \(offset + 1) 본문 문단 \($0)")
                }
                return HwpSynthetic.section(
                    firstParagraphControls: controls,
                    bodyParagraphs: (leadingBodyParagraphsBySection[offset] ?? []) + body
                )
            }
            return HwpPaginator(
                sections: sections,
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 모든 쪽의 쪽 번호 텍스트 (쪽 순서).
        func pageNumberTexts(of paginator: HwpPaginator) async throws -> [[String]] {
            let totalPages = await paginator.totalPages()
            var texts: [[String]] = []
            for pageIndex in 0 ..< totalPages {
                await texts.append(pageNumberTexts(of: try paginator.page(at: pageIndex)))
            }
            return texts
        }

        func makePaginator(
            firstParagraphControls: [CoreHwp.HwpCtrlId],
            leadingBodyParagraphs: [CoreHwp.HwpParagraph] = []
        ) throws -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: firstParagraphControls,
                bodyParagraphs: leadingBodyParagraphs + (try (0 ..< 30).map {
                    try HwpSynthetic.textParagraph("본문 문단 \($0)")
                })
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 본문 밖 (콘텐츠 아래/위 밴드)에 있는 텍스트 블록의 전체 문자열 =
        /// 쪽 번호 후보. 본문 텍스트 ("본문 문단 3")와 구분하기 위해
        /// 콘텐츠 프레임 밖의 블록만 모은다.
        func pageNumberTexts(of page: HwpPage?) -> [String] {
            guard let page else { return [] }
            let contentTop = page.margins.top
            let contentBottom = page.size.height - page.margins.bottom
            return page.blocks.compactMap { block -> String? in
                guard block.kind == .text,
                      let text = block.attributedString?.string,
                      block.frame.minY >= contentBottom - 0.5
                      || block.frame.maxY <= contentTop + 0.5
                else { return nil }
                return text
            }
        }

        func allTexts(of paginator: HwpPaginator, pageIndex: Int) async throws -> [String] {
            let page = try await paginator.page(at: pageIndex)
            return (page?.blocks ?? []).compactMap(\.attributedString?.string)
        }
    }
#endif
