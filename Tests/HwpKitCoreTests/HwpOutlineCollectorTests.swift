@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개요·책갈피 탐색 목록 수집 (#77) — 합성 문서로 규약을 고정한다.
    ///
    /// 실측 핀(헌법주석의 개요 문단 1,944개·수준 분포·`개요 N` ↔ 비트 `N-1`)은
    /// `HwpOutlineFixtureTests`가 따로 잡는다. 여기서는 조판이 개입하는 축만
    /// 본다 — 쪽 귀속, 컨테이너 스코프, 재조판 멱등.
    final class HwpOutlineCollectorTests: XCTestCase {
        // MARK: - 수준 판정

        func testHeadingLevelComesFromParagraphLevelBitsAndIsOneBased() async throws {
            // 저장값 0..6 = 개요 1~7. 사람이 읽는 수준은 +1이다.
            let shapes = Dictionary(uniqueKeysWithValues: (UInt32(0) ... 6).map { level in
                (level + 1, HwpSynthetic.outlineParaShape(levelRawValue: level))
            })
            let bodyParagraphs = try (UInt32(0) ... 6).map { level in
                try HwpSynthetic.styledParagraph("제목 \(level)", paraShapeId: UInt16(level) + 1)
            }
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: bodyParagraphs, index: HwpSynthetic.outlineIndex(paraShapes: shapes)
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            expect(outline.map(\.level)) == [1, 2, 3, 4, 5, 6, 7]
            expect(outline.map(\.title)) == (0 ... 6).map { "제목 \($0)" }
            expect(outline.allSatisfy { $0.kind == .heading }) == true
            expect(outline.map(\.ordinal)) == Array(0 ... 6)
            expect(outline.map(\.id)) == outline.map(\.ordinal)
        }

        /// 3비트는 0...7 = 1수준~**8**수준을 담는다 ("3비트라 7수준까지"가 아니다).
        func testHeadingLevelBitsReachEighthLevel() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try HwpSynthetic.styledParagraph("여덟째", paraShapeId: 1)],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 7)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.level)) == [8]
        }

        /// **옆에 있는 `collectUnsupportedNumberingHeading`의 가드를 복사하면 안 된다.**
        /// 그 가드는 `numberingOrBulletId > 0`을 요구하는데 실문서 개요 paraShape의
        /// 그 값은 전 픽스처에서 0이다 — 베끼면 헌법주석의 개요 1,944개 중 0개가
        /// 수집되고 사이드바가 조용히 빈다.
        func testHeadingWithoutNumberingIdIsStillCollected() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try HwpSynthetic.styledParagraph("번호 정의 없는 개요", paraShapeId: 1)],
                index: HwpSynthetic.outlineIndex(paraShapes: [
                    1: HwpSynthetic.outlineParaShape(levelRawValue: 0, numberingOrBulletId: 0),
                ])
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let unsupported = await paginator.unsupportedElements()

            expect(outline.map(\.title)) == ["번호 정의 없는 개요"]
            // 그 진단은 numberingOrBulletId > 0에서만 발화하므로 여기서는 없다.
            expect(unsupported.map(\.hint).filter { $0.contains("개요") }) == []
        }

        /// 같은 문단이 미지원 목록과 탐색 목록에 **동시에** 뜨는 것은 의도다 —
        /// 개요를 탐색 대상으로 승격시켜도 생성 라벨을 렌더하게 되는 것은 아니다.
        func testHeadingIsReportedBothAsOutlineAndAsUnrenderedLabel() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try HwpSynthetic.styledParagraph("번호 정의 있는 개요", paraShapeId: 1)],
                index: HwpSynthetic.outlineIndex(paraShapes: [
                    1: HwpSynthetic.outlineParaShape(levelRawValue: 1, numberingOrBulletId: 1),
                ])
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let unsupported = await paginator.unsupportedElements()

            expect(outline.map(\.title)) == ["번호 정의 있는 개요"]
            expect(outline.map(\.level)) == [2]
            expect(unsupported.map(\.hint)).to(contain("개요 번호 문단 머리 (미렌더)"))
        }

        /// 스타일 이름 폴백은 대안이 아니라 상시 병행 경로다 — `개요 8` 이상
        /// 스타일은 머리 모양이 개요로 설정돼 있지 않아 비트 경로로는 원리적으로
        /// 잡히지 않는다 (헌법주석 실측: `개요 8`·`개요 9` → paraShape raw `0x180`).
        func testStyleNameFallbackCatchesOutlineStylesWithoutHeadingBits() async throws {
            let bodyParagraphs = [
                try HwpSynthetic.styledParagraph("여덟째 수준", paraShapeId: 1, paraStyleId: 19),
                try HwpSynthetic.styledParagraph("아홉째 수준", paraShapeId: 1, paraStyleId: 20),
                try HwpSynthetic.styledParagraph("열째 수준", paraShapeId: 1, paraStyleId: 21),
                try HwpSynthetic.styledParagraph("영문 스타일", paraShapeId: 1, paraStyleId: 22),
                try HwpSynthetic.styledParagraph("본문", paraShapeId: 1, paraStyleId: 23),
            ]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: bodyParagraphs,
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.plainParaShape()],
                    styles: [
                        19: HwpSynthetic.outlineStyle("개요 8"),
                        20: HwpSynthetic.outlineStyle("개요 9"),
                        21: HwpSynthetic.outlineStyle("개요 10"),
                        22: HwpSynthetic.outlineStyle("본문", english: "Outline 4"),
                        23: HwpSynthetic.outlineStyle("바탕글", english: "Normal"),
                    ]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            expect(outline.map(\.title)) == ["여덟째 수준", "아홉째 수준", "열째 수준", "영문 스타일"]
            expect(outline.map(\.level)) == [8, 9, 10, 4]
        }

        /// 상한을 넘는 스타일 이름은 **버리지 않고** 클램프한다 — 거부하면 사용자가
        /// 만든 깊은 개요 스타일의 제목이 목록에서 조용히 사라진다. 수준은 들여쓰기
        /// 힌트일 뿐이고 쪽 번호는 그대로라 탐색은 성립한다.
        func testStyleLevelBeyondTheMaximumIsClampedNotDropped() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph("열두째 수준", paraShapeId: 1, paraStyleId: 30),
                    try HwpSynthetic.styledParagraph("조작된 수준", paraShapeId: 1, paraStyleId: 31),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.plainParaShape()],
                    styles: [
                        30: HwpSynthetic.outlineStyle("개요 12"),
                        31: HwpSynthetic.outlineStyle("본문", english: "Outline 999"),
                    ]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            let clamped: [Int?] = [HwpOutlineItem.maximumLevel, HwpOutlineItem.maximumLevel]
            expect(outline.map(\.title)) == ["열두째 수준", "조작된 수준"]
            expect(outline.map(\.level)) == clamped
        }

        /// 비트 경로가 있으면 그쪽이 이긴다 — 두 경로가 갈릴 때의 우선순위를 고정한다.
        func testHeadingBitsWinOverStyleName() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph("제목", paraShapeId: 1, paraStyleId: 8),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 2)],
                    styles: [8: HwpSynthetic.outlineStyle("개요 7", english: "Outline 7")]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.level)) == [3]
        }

        func testNonOutlineParagraphsProduceNoItems() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph("그냥 본문", paraShapeId: 1, paraStyleId: 1),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.plainParaShape()],
                    styles: [1: HwpSynthetic.outlineStyle("바탕글", english: "Normal")]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        func testBlankDocumentHasEmptyOutline() async {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        // MARK: - 제목 정규화

        func testTitleStripsControlMarkersAndCollapsesWhitespace() async throws {
            var heading = try HwpSynthetic.styledParagraph("", paraShapeId: 1)
            var paraText = CoreHwp.HwpParaText()
            // 한 식으로 이으면 CI 러너의 타입 체커가 시간 초과한다 (로컬은 통과).
            var chars: [CoreHwp.HwpChar] = "가".utf16
                .map { CoreHwp.HwpChar(type: .char, value: $0) }
            chars.append(CoreHwp.HwpChar(type: .char, value: 9)) // 탭 → 공백
            chars.append(CoreHwp.HwpChar(type: .extended, value: 11)) // 개체 마커 → 제거
            chars.append(CoreHwp.HwpChar(type: .char, value: 32))
            chars.append(contentsOf: "나".utf16
                .map { CoreHwp.HwpChar(type: .char, value: $0) })
            chars.append(CoreHwp.HwpChar(type: .char, value: 13)) // 문단 끝 → 공백 → trim
            paraText.charArray = chars
            heading.paraText = paraText
            heading.paraLineSeg.paraLineSegInternalArray = []
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [heading],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["가 나"]
        }

        func testEmptyTitleHeadingIsSkipped() async throws {
            var heading = try HwpSynthetic.styledParagraph("   ", paraShapeId: 1)
            heading.paraLineSeg.paraLineSegInternalArray = []
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [heading],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        func testLongTitleIsClippedToLimitWithoutEllipsis() async throws {
            let long = String(repeating: "가", count: HwpOutlineItem.titleCharacterLimit + 50)
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try HwpSynthetic.styledParagraph(long, paraShapeId: 1)],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let title = try XCTUnwrap(outline.first?.title)

            expect(title.count) == HwpOutlineItem.titleCharacterLimit
            expect(long.hasPrefix(title)) == true
        }

        /// 상한은 **Character(grapheme) 단위**다 — UTF-16 배수로 근사하면 ZWJ
        /// 시퀀스(가족 이모지는 grapheme당 11단위)에서 상한에 한참 못 미치는 자리를
        /// 끊는다 (종전 4배 컷은 아래 100자 제목을 72자로 줄였다).
        func testEmojiTitleIsCappedByCharactersNotUtf16Units() async throws {
            let family = "👨‍👩‍👧‍👦"
            let short = String(repeating: family, count: 100)
            let long = String(repeating: family, count: HwpOutlineItem.titleCharacterLimit + 50)
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph(short, paraShapeId: 1),
                    try HwpSynthetic.styledParagraph(long, paraShapeId: 1),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let titles = await paginator.outline().map(\.title)

            // 상한 아래 제목(1,100 UTF-16 단위)은 온전히 남는다.
            expect(titles.first) == short
            expect(titles.last?.count) == HwpOutlineItem.titleCharacterLimit
        }

        /// 안전판에 걸려도 **대리 쌍 중간에서는 끊지 않는다** — 끊으면
        /// `String(decoding:)`이 U+FFFD로 복구해 "평문의 접두" 계약이 깨진다.
        ///
        /// 입력이 기괴한 데는 이유가 있다. U+FFFD가 **관측되려면** 두 조건이 함께
        /// 서야 한다: ① 절단 지점이 상위 대리여야 하고, ② 그 지점이 상한(200자)
        /// **안**이어야 한다 — 뒤쪽이면 `collapsedWhitespace`의 prefix가 버려서
        /// 단언이 공허해진다 (초안이 그랬다: 2단위 문자로는 절단이 3,200번째
        /// 문자라 무력화 실험에서도 통과했다). grapheme을 79단위(SMP 기반 +
        /// 결합 문자 77)로 잡으면 `6,399 = 79 × 81`이라 천장(6,400)이 82번째
        /// grapheme의 상위 대리에 정확히 떨어지고, 82자는 상한 안이라 남는다.
        func testCeilingDoesNotSplitSurrogatePairs() async throws {
            let cluster = "𝄞" + String(repeating: "\u{0301}", count: 77)
            let text = String(repeating: cluster, count: 82)
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [try HwpSynthetic.styledParagraph(text, paraShapeId: 1)],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let title = try XCTUnwrap(outline.first?.title)

            expect(title.unicodeScalars.contains("\u{FFFD}")) == false
            // 81개 온전한 cluster + 마지막 기반 문자 하나 = 82자.
            expect(title.count) == 82
        }

        /// 자릿수가 `Int`를 넘어도 **클램프**다. nil로 두면 제목이 목록에서
        /// 조용히 사라져 "상한을 넘으면 거부가 아니라 클램프"라는 정책과 어긋난다.
        /// 앞자리 0은 `Int`가 흡수하므로(실측 `Int("0…01") == 1`) 대상이 아니다.
        func testOversizedStyleLevelDigitsAreClampedNotDropped() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try HwpSynthetic.styledParagraph("거대 수준", paraShapeId: 1, paraStyleId: 9),
                    try HwpSynthetic.styledParagraph("앞자리 0", paraShapeId: 1, paraStyleId: 10),
                ],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.plainParaShape()],
                    styles: [
                        9: HwpSynthetic.outlineStyle("개요 99999999999999999999999"),
                        10: HwpSynthetic.outlineStyle("개요 0000000000000000000000003"),
                    ]
                )
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            expect(outline.map(\.title)) == ["거대 수준", "앞자리 0"]
            expect(outline.map(\.level)) == [HwpOutlineItem.maximumLevel, 3]
        }

        /// 스타일 이름 폴백은 `paraStyleId`로 메모한다 — **nil도 캐시한다**.
        /// 이름은 최대 65,535 UTF-16 단위인데 개요가 아닌 문단은 두 이름을 모두
        /// 훑으므로(문단당 4벌), 그 nil을 안 담으면 가장 흔한 경로가 그대로 남아
        /// 작은 파일이 이름 길이 × 문단 수로 증폭한다.
        func testStyleLevelIsMemoizedPerStyleIdIncludingNil() throws {
            let index = HwpSynthetic.outlineIndex(
                paraShapes: [1: HwpSynthetic.plainParaShape()],
                styles: [
                    7: HwpSynthetic.outlineStyle("바탕글", english: "Normal"),
                    8: HwpSynthetic.outlineStyle("개요 3", english: "Outline 3"),
                ]
            )
            let plain = try HwpSynthetic.styledParagraph("본문", paraShapeId: 1, paraStyleId: 7)
            let heading = try HwpSynthetic.styledParagraph("제목", paraShapeId: 1, paraStyleId: 8)
            var collector = HwpOutlineCollector(index: index)

            for _ in 0 ..< 5 {
                for paragraph in [plain, heading] {
                    collector.collect(
                        from: paragraph,
                        headingPage: 1,
                        bookmarkPage: 1,
                        maximumPage: 1,
                        childParagraphs: { _, _ in [] }
                    )
                }
            }

            // 스타일 2종을 10번 통과했지만 이름을 훑은 것은 2회뿐이다.
            expect(collector.styleParseCount) == 2
            expect(collector.items.compactMap(\.level)) == [3, 3, 3, 3, 3]
        }

        /// 책갈피 이름도 제목과 **같은 UTF-16 천장**을 지난다 — `collapsedWhitespace`의
        /// 상한은 Character 수라, 기반 문자 하나에 결합 문자가 수만 개 붙은 이름은
        /// grapheme 하나(= 1자)로 세어져 상한을 그냥 통과하고 128KB가 그대로
        /// `metadata.outline`에 상주한다 (항목 상한 20,000개와 곱해진다).
        func testBookmarkNameIsCappedByTheUnitCeiling() async throws {
            let name = "가" + String(repeating: "\u{0301}", count: 20000)
            var host = try HwpSynthetic.styledParagraph("본문", paraShapeId: 1)
            host.ctrlHeaderArray = [HwpSynthetic.bookmarkControl(name)]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host],
                index: HwpSynthetic.outlineIndex(paraShapes: [1: HwpSynthetic.plainParaShape()])
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let title = try XCTUnwrap(outline.first?.title)

            expect(title.utf16.count) == HwpOutlineCollector.titleUnitCeiling
            // 잘린 결과는 UTF-16 단위로 원본의 접두다 — `hasPrefix`는 grapheme
            // 기준이라 잘린 cluster에는 쓸 수 없다.
            expect(Array(title.utf16)) == Array(name.utf16.prefix(title.utf16.count))
        }
    }
#endif
