import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 줄마다 상자 높이가 다른 문단의 **상자 상단** 계약 (#178 리뷰).
    ///
    /// 앵커 자체는 `HwpBaselineAnchorTests`가 잠근다. 여기서 잠그는 것은 그 앵커를 걸 자리,
    /// 즉 CT 슬롯에서 복원한 **배치 ascent**다 — 줄 높이를 못박지 않은 문단 (`.atLeast`·
    /// 개체 문단·공개 `HwpPaintCommand.drawText` 호출자) 은 줄마다 슬롯이 달라 여기가
    /// 어긋나면 글자가 상자를 벗어난다.
    ///
    /// 오라클은 CT 자신이다 — 프레임 높이를 줄여 줄이 떨어지는 임계를 이분 탐색하면 CT의
    /// 실제 슬롯 경계가 나온다 (2026-09-13 실측). 그 경계가 말해 주는 것이 이 스위트가 지키는
    /// 규칙이다: 슬롯의 baseline 아래 몫은 보고 **descent**이고 (`leading`은 위쪽 몫이며 보고
    /// **ascent**는 배치값이 아니다), 문단 간격·줄 뒤 간격은 다음 슬롯의 ascent 안에 들어
    /// 있어 걷어내야 하며, 그 간격은 줄 간격 하한·상한에 갇힌 **유효** 값이다.
    ///
    /// 균일한 문단은 이 복원식을 타지 않으므로 (`hasUniformSlots`) 여기 가드들은 **줄마다
    /// 상자가 다른** 문단을 쓴다 — 균일한 입력으로 잠그면 판별력이 없다.
    final class HwpLineBoxAdvanceTests: XCTestCase {
        /// **상한만 지정된 문단은 못박힌 문단이 아니다** (#178 리뷰). 상한은 그 아래 높이를
        /// 전혀 건드리지 않으므로 CT 조판이 그대로인데, 상한만을 못박힌 쪽으로 보면 청크 첫
        /// 줄의 배치 ascent가 모든 줄에 적용돼 상자가 어긋난다 — 이 문단에서 무해한 상한
        /// 1000을 얹으면 baseline이 `[108.5, 151.9, 199.9]` → `[108.5, 175.0, 223.0]`으로
        /// 바뀌었다.
        func testNoOpMaximumLineHeightMovesNoLine() {
            let plain = LineBoxFixtures.baselines(LineBoxFixtures.mixedSizeParagraph())
            let capped = LineBoxFixtures.baselines(
                LineBoxFixtures.mixedSizeParagraph(maximumLineHeight: 1000)
            )
            expect(plain.count).to(equal(3))
            expect(capped.map(Double.init))
                .to(beCloseTo(plain.map(Double.init), within: 0.001))
        }

        // **하한이 걸린 줄과 자연 높이가 더 큰 줄은 슬롯이 다르다** (#178 리뷰).
        // 10pt 상자에 하한 20을 걸면 한글의 전진량은 `max(상자, 하한)` = 20pt이고, 뒤따르는
        // 40pt 줄은 하한보다 크므로 자기 자연 슬롯을 쓴다. 줄별 **보고** ascent로 상자를
        // 찾던 종전 구현은 CT가 늘린 슬롯의 여분을 보고에서 빼먹어 둘째 줄 상자를 8.2pt
        // 아래에 뒀다.

        /// **하한이 걸린 줄과 자연 높이가 더 큰 줄은 슬롯이 다르다** (#178 리뷰).
        /// 10pt 상자에 하한 20을 걸면 한글의 전진량은 `max(상자, 하한)` = 20pt이고, 뒤따르는
        /// 40pt 줄은 하한보다 크므로 자기 자연 슬롯을 쓴다. 줄별 **보고** ascent로 상자를
        /// 찾던 종전 구현은 CT가 늘린 슬롯의 여분을 보고에서 빼먹어 둘째 줄 상자를 8.2pt
        /// 아래에 뒀다.
        func testMinimumOnlyLineHeightAdvancesShortLinesByTheMinimum() {
            let baselines = LineBoxFixtures.baselines(
                LineBoxFixtures.mixedSizeParagraph(minimumLineHeight: 20)
            )
            expect(baselines.count).to(equal(3))
            guard baselines.count == 3 else { return }
            // 첫 줄 상자(10pt)는 블록 상단에 핀한다.
            expect(Double(baselines[0])).to(beCloseTo(100 + 8.5, within: 0.001))
            // 둘째 줄 상자 상단 = 100 + max(10, 20) → baseline은 그 아래 0.85 × 40.
            expect(Double(baselines[1])).to(beCloseTo(100 + 20 + 34, within: 0.01))
        }

        // **줄 간격 하한·상한을 적용한 유효 간격을 써야 한다** (#178 리뷰). CT는
        // `lineSpacingAdjustment`를 `minimumLineSpacing`·`maximumLineSpacing`으로 가두므로,
        // 상한 4에 간격 4와 10을 준 두 문단은 CT에서 **같은 자리**에 조판된다 — 원시 간격을
        // 그대로 빼던 동안에는 우리가 그 둘을 6pt 다르게 그렸다. 하한도 같다(간격 0과 2가
        // 하한 8 아래에서 같다).

        /// **줄 간격 하한·상한을 적용한 유효 간격을 써야 한다** (#178 리뷰). CT는
        /// `lineSpacingAdjustment`를 `minimumLineSpacing`·`maximumLineSpacing`으로 가두므로,
        /// 상한 4에 간격 4와 10을 준 두 문단은 CT에서 **같은 자리**에 조판된다 — 원시 간격을
        /// 그대로 빼던 동안에는 우리가 그 둘을 6pt 다르게 그렸다. 하한도 같다(간격 0과 2가
        /// 하한 8 아래에서 같다).
        func testLineSpacingBoundsMakeEqualCoreTextLayoutsEqual() {
            for pair in [
                (a: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(4)),
                     (.maximumLineSpacing, 4)],
                 b: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(10)),
                     (.maximumLineSpacing, 4)]),
                (a: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(0)),
                     (.minimumLineSpacing, 8)],
                 b: [(CTParagraphStyleSpecifier.lineSpacingAdjustment, CGFloat(2)),
                     (.minimumLineSpacing, 8)]),
            ] {
                // 줄마다 상자가 다른 문단이어야 복원식을 타 간격 계산이 드러난다 —
                // 균일한 문단은 슬롯이 균일해 첫 줄의 정확값만으로 배치된다.
                let first = LineBoxFixtures.mixedSizeParagraph(spacing: pair.a)
                let second = LineBoxFixtures.mixedSizeParagraph(spacing: pair.b)
                // 전제: CT가 둘을 같은 자리에 조판한다 (줄 origin 델타가 같다).
                expect(LineBoxFixtures.coreTextDeltas(first)).to(
                    beCloseTo(LineBoxFixtures.coreTextDeltas(second), within: 0.001),
                    description: "CT 조판이 같아야 이 가드가 뜻이 있다"
                )
                let width = LineBoxFixtures.paragraphWidth
                let firstBaselines = LineBoxFixtures.baselines(first, lineWidth: width)
                let secondBaselines = LineBoxFixtures.baselines(second, lineWidth: width)
                expect(firstBaselines.map(Double.init))
                    .to(beCloseTo(secondBaselines.map(Double.init), within: 0.001))
            }
        }

        // **글꼴 leading은 baseline 아래 몫이 아니다** (#178 리뷰). CT는 leading을 슬롯의
        // baseline **위**에 넣으므로 `descent + leading`을 아래 몫으로 쓰면 leading이 있는
        // 글꼴에서 상자가 그만큼 어긋난다 (Hiragino Sans 5.0pt·Times New Roman 0.42pt·
        // Arial 0.33pt). 오라클은 CT 자신이다 — 프레임 높이를 줄여 첫 줄이 떨어지는 임계가
        // 곧 첫 슬롯 높이이고, 그것이 첫 줄에서 둘째 줄 상자까지의 전진량이다.

        /// **문단 간격은 상자 사이에 남는다.** CT는 문단 아래·위 간격을 다음 줄 슬롯의
        /// ascent 안에 넣으므로 (실측: 간격 6+4를 준 둘째 문단 첫 줄의 배치 ascent가
        /// 9.70 → 19.70) 배치 ascent 복원에서 걷어내야 한다. 걷어내지 않으면 간격이 사라져
        /// 둘째 문단이 그만큼 올라간다 — 한글은 줄 간격 여분을 상자 아래 `lineSpacing`으로
        /// 적고 다음 상자를 그 아래에 둔다.
        func testParagraphSpacingStaysBetweenLineBoxes() {
            let plain = LineBoxFixtures.baselines(
                LineBoxFixtures.twoParagraphs(spacing: 0, before: 0)
            )
            let spaced = LineBoxFixtures.baselines(
                LineBoxFixtures.twoParagraphs(spacing: 6, before: 4)
            )
            expect(plain.count).to(equal(2))
            expect(spaced.count).to(equal(2))
            guard plain.count == 2, spaced.count == 2 else { return }
            expect(Double(spaced[0])).to(beCloseTo(Double(plain[0]), within: 0.001))
            expect(Double(spaced[1] - plain[1])).to(beCloseTo(10, within: 0.001))
        }

        // 문단 아래·위 간격을 실은 10pt 두 문단
    }

    /// 강제 줄 높이가 걸린 문단의 **아래 몫** 계약 (#178 리뷰).
    ///
    /// CT는 양쪽 정렬 줄의 typographic bounds에 강제 줄 높이를 적용하기 **전** descent를
    /// 담으므로, 하한이 세우는 바닥 (`하한 − 그 줄 ascent`) 이 없으면 하한이 걸린 문단의 줄들이
    /// 어긋난다. 한글 문단은 기본이 양쪽 정렬이라 실물이 이 조건이다.
    final class HwpLineBoxClampTests: XCTestCase {
        /// **혼합 크기 문단에서도 하한이 걸린 줄의 아래 몫을 지켜야 한다** (#178 리뷰).
        /// 마지막 글자만 커져 줄 상자가 갈리면 앞의 양쪽 정렬 줄까지 복원식으로 가는데, 그 줄의
        /// 보고 descent는 클램프 **전** 값이라 (하한 20pt·10pt 글자: 보고 2.2998, 실제 6.0)
        /// 하한이 세우는 바닥이 없으면 첫 간격이 20 → 16.30pt로 줄고, 청크로 나누면 다시 20이
        /// 되어 예산에 따라 출력이 갈렸다.
        func testMixedSizeJustifiedParagraphKeepsTheClampedBelowBaseline() {
            var rendered = [[Double]]()
            for budget in [100_000, 40, 20] {
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: LineBoxFixtures.justifiedTailParagraph(),
                    origin: CGPoint(x: 0, y: 100), lineWidth: 30, maxLineFrames: budget
                ).map { Double($0.baselineOrigin.y) }
                expect(lines.count).to(beGreaterThan(3), description: "예산 \(budget)")
                guard lines.count > 3 else { continue }
                // 하한 20pt가 걸린 줄들은 정확히 20pt 간격이다 (마지막 큰 줄은 자기 슬롯).
                let gaps = zip(lines.dropFirst(), lines).map { $0 - $1 }
                expect(Array(gaps.dropLast())).to(
                    beCloseTo(Array(repeating: 20.0, count: gaps.count - 1), within: 0.01),
                    description: "예산 \(budget)"
                )
                rendered.append(lines)
            }
            for lines in rendered.dropFirst() {
                expect(lines).to(beCloseTo(rendered[0], within: 0.01), description: "예산 무관")
            }
        }

        /// **높이가 다른 두 문단을 한 슬롯으로 보면 안 된다** (#178 리뷰). 한 블록에 20pt·60pt로
        /// 못박은 두 문단이 들어가면 첫 문단 줄의 슬롯은 20pt이므로 둘째 문단 첫 줄 상자 상단은
        /// 그 아래 20pt (임계 실측 119.9999) 다 — 뒤에 줄을 하나 더 붙여도 그 자리가 변해선
        /// 안 된다. 종전에는 두 줄일 때 148.5, 세 줄일 때 128.5로 갈렸다.
        func testDifferentPinnedHeightsInOneBlockDoNotShareASlot() {
            let two = LineBoxFixtures.baselines(
                LineBoxFixtures.twoPinnedParagraphs(extraLine: false), lineWidth: 200
            )
            let three = LineBoxFixtures.baselines(
                LineBoxFixtures.twoPinnedParagraphs(extraLine: true), lineWidth: 200
            )
            expect(two.count).to(equal(2))
            expect(three.count).to(equal(3))
            guard two.count == 2, three.count == 3 else { return }
            expect(Double(two[1])).to(beCloseTo(100 + 20 + 8.5, within: 0.01))
            expect(Double(three[1])).to(beCloseTo(Double(two[1]), within: 0.01))
        }

        /// **글꼴 leading은 baseline 아래 몫이 아니다** (#178 리뷰). CT는 leading을 슬롯의
        /// baseline **위**에 넣으므로 `descent + leading`을 아래 몫으로 쓰면 leading이 있는
        /// 글꼴에서 상자가 그만큼 어긋난다 (Hiragino Sans 5.0pt·Times New Roman 0.42pt·
        /// Arial 0.33pt). 오라클은 CT 자신이다 — 프레임 높이를 줄여 첫 줄이 떨어지는 임계가
        /// 곧 첫 슬롯 높이이고, 그것이 첫 줄에서 둘째 줄 상자까지의 전진량이다.
        func testFontLeadingIsNotCountedBelowTheBaseline() throws {
            let name = try XCTUnwrap(
                LineBoxFixtures.nameOfFontWithLeading(), "leading이 있는 글꼴이 없는 기기"
            )
            // 줄마다 상자가 다른 문단이어야 복원식을 타 아래쪽 몫이 드러난다.
            let string = LineBoxFixtures.mixedSizeParagraph(fontName: name)
            let lines = LineBoxFixtures.baselines(string, lineWidth: 400)
            expect(lines.count).to(equal(3))
            guard lines.count == 3 else { return }
            // 첫 줄 상자 전진량 = CT가 첫 줄에 쓴 슬롯 (임계 오라클).
            let slot = try XCTUnwrap(LineBoxFixtures.measuredFirstSlot(string, width: 400))
            let secondBoxTop = lines[1] - 40 * HwpRenderTuning.Text.baselineAnchorRatio
            expect(Double(secondBoxTop - 100)).to(beCloseTo(Double(slot), within: 0.01))
        }

        // 이 기기에서 leading이 0이 아닌 글꼴 이름 (없으면 nil). `CTFontCreateWithName`은
        // 모르는 이름에 Helvetica(leading 0)를 주므로 leading 검사로 걸러진다.

        /// **양쪽 정렬 문단에서도 줄 전진량이 균일해야 한다.** CT는 양쪽 정렬 줄의
        /// typographic bounds에 강제 줄 높이를 **적용하기 전** 값을 담는다 (하한 15pt·
        /// Helvetica 10pt: 보고 descent 2.2998, 실제 배치 4.0). 보고값으로 복원하면 줄마다
        /// 1.7pt 어긋나므로, 슬롯이 균일한 것이 관찰되면 첫 줄의 정확값을 그대로 쓴다.
        func testJustifiedClampedParagraphKeepsAUniformAdvance() {
            let string = LineBoxFixtures.uniformParagraph(
                specs: [(.minimumLineHeight, 15)], justified: true
            )
            let lines = LineBoxFixtures.baselines(string, lineWidth: LineBoxFixtures.paragraphWidth)
            expect(lines.count).to(beGreaterThan(2))
            guard lines.count > 2 else { return }
            let gaps = zip(lines.dropFirst(), lines).map { Double($0 - $1) }
            expect(gaps).to(beCloseTo(Array(repeating: 15.0, count: gaps.count), within: 0.01))
        }

        // 같은 문단은 **청크를 어떻게 나눠도** 같은 자리에 그려져야 한다 — `maxLineFrames`는
        // 문자 예산이라 작은 값이 청크를 쪼갠다. 균일한 문단은 청크마다 CT 첫 줄 슬롯 특례를
        // 새로 타므로, 그 특례가 전진량에 새면 경계마다 자리가 밀린다.

        /// **이월 청크가 새 프레임의 첫 슬롯 특례를 다시 타면 안 된다** (#178 리뷰). CT는 프레임
        /// 첫 슬롯을 뒤 슬롯보다 크게 잡으므로 (leading 0 글꼴 0.3pt, Hiragino Sans 5.0pt) 이월
        /// 때 그 값을 기준으로 복원하면 경계마다 특례가 되풀이돼 뒤 줄이 밀린다 — 실측: Hiragino
        /// Sans 하한 10pt 문단이 예산 20에서 33.6pt, 13에서 14.4pt 어긋났다. 버린 줄의 배치
        /// ascent를 넘기면 예산과 무관해진다.
        func testCarryoverKeepsThePlacementAscentAcrossFrames() throws {
            let name = try XCTUnwrap(
                LineBoxFixtures.nameOfFontWithLeading(), "leading이 있는 글꼴이 없는 기기"
            )
            let string = LineBoxFixtures.uniformParagraph(
                specs: [(.minimumLineHeight, 10)], fontName: name
            )
            let whole = LineBoxFixtures.baselines(string, lineWidth: 60)
            expect(whole.count).to(beGreaterThan(4))
            for budget in [13, 20, 40] {
                let chunked = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: CGPoint(x: 0, y: 100),
                    lineWidth: 60, maxLineFrames: budget
                ).map(\.baselineOrigin.y)
                expect(chunked.count).to(equal(whole.count), description: "예산 \(budget)")
                guard chunked.count == whole.count else { continue }
                expect(chunked.map(Double.init)).to(
                    beCloseTo(whole.map(Double.init), within: 0.01), description: "예산 \(budget)"
                )
            }
        }

        /// **미완 줄의 ascent를 완성된 줄에 그대로 쓰면 안 된다** (#178 리뷰). 이월이 넘기는
        /// 배치 ascent는 **미완이던** 줄의 값이고, 그 줄은 다음 청크에서 온전히 재조판되며 큰
        /// 개체를 얻을 수 있다 — 하한 20pt 문단의 14pt를 60pt 개체 줄에 쓰면 다음 텍스트 줄이
        /// 개체 줄보다 위로 올라가 겹친다 (실측: 개체 위치 × 예산 스윕에서 역전 16건, 전체 조판
        /// 대비 최대 42.3pt). 슬롯 지표(상자 높이·개체 예약·글꼴 ascent)가 같을 때만 쓴다.
        func testCarryoverIgnoresAStaleAscentWhenTheLineGainsAnObject() {
            for position in [20, 28, 32, 36] {
                let string = LineBoxFixtures.paragraphWithObject(at: position)
                let whole = LineBoxFixtures.baselines(string, lineWidth: 80)
                for budget in [20, 24, 28, 32] {
                    let chunked = HwpDrawnTextLayout.lines(
                        attributedString: string, origin: CGPoint(x: 0, y: 100),
                        lineWidth: 80, maxLineFrames: budget
                    ).map(\.baselineOrigin.y)
                    let label = "개체 \(position)·예산 \(budget)"
                    // baseline은 언제나 단조증가해야 한다 (역전 = 글자가 앞 줄 위로 올라간 것).
                    for index in 1 ..< chunked.count {
                        expect(chunked[index]).to(
                            beGreaterThan(chunked[index - 1]), description: label
                        )
                    }
                    guard chunked.count == whole.count else { continue }
                    expect(chunked.map(Double.init)).to(
                        beCloseTo(whole.map(Double.init), within: 0.01), description: label
                    )
                }
            }
        }

        /// **프레임 첫 슬롯의 하한은 음수 간격으로 내리지 않는다** (#178 리뷰). CT는 첫 줄 앞에
        /// 간격을 넣지 않으므로 첫 슬롯은 하한 그대로다 (하한 20·간격 −6에서 슬롯 20·14·14·14).
        /// 첫 줄까지 바닥을 내리면 양쪽 정렬 문단의 클램프 전 descent를 받아 내지 못해 둘째 줄부터
        /// 3.7002pt 올라갔다 — 정렬만 바꿔도 세로 위치가 달라져선 안 된다.
        func testFirstSlotKeepsItsMinimumUnderNegativeLineSpacing() {
            let specs: [(CTParagraphStyleSpecifier, CGFloat)] = [
                (.minimumLineHeight, 20), (.lineSpacingAdjustment, -6),
            ]
            let natural = LineBoxFixtures.baselines(
                LineBoxFixtures.uniformParagraph(specs: specs), lineWidth: 60
            )
            let justified = LineBoxFixtures.baselines(
                LineBoxFixtures.uniformParagraph(specs: specs, justified: true), lineWidth: 60
            )
            expect(natural.count).to(beGreaterThan(3))
            expect(justified.count).to(equal(natural.count))
            guard natural.count == justified.count else { return }
            expect(justified.map(Double.init))
                .to(beCloseTo(natural.map(Double.init), within: 0.01))
            // 첫 전진량은 첫 슬롯(하한 20pt)이고 그 뒤는 줄어든 슬롯(14pt)이다.
            let gaps = zip(natural.dropFirst(), natural).map { Double($0 - $1) }
            expect(gaps[0]).to(beCloseTo(20.0, within: 0.01))
            expect(Array(gaps.dropFirst())).to(
                beCloseTo(Array(repeating: 14.0, count: gaps.count - 1), within: 0.01)
            )
        }

        /// **음수 줄 간격은 슬롯 하한도 낮춘다** (#178 리뷰). 하한 20pt에 줄 뒤 간격 −6을 주면
        /// CT는 슬롯을 14pt로 줄이는데 (첫 슬롯만 20pt) 하한을 그대로 바닥으로 쓰면 아래 몫이
        /// 6.0 대신 12.0이 되어 둘째 줄부터 6pt씩 밀렸다 — 임계 실측 상자 상단은
        /// 100 / 119.9999 / 133.9999 / 148.0이다.
        func testNegativeLineSpacingLowersTheMinimumSlot() {
            let string = LineBoxFixtures.uniformParagraph(
                specs: [(.minimumLineHeight, 20), (.lineSpacingAdjustment, -6)]
            )
            let baselines = LineBoxFixtures.baselines(string, lineWidth: 60)
            expect(baselines.count).to(beGreaterThan(3))
            guard baselines.count > 3 else { return }
            let gaps = zip(baselines.dropFirst(), baselines).map { Double($0 - $1) }
            // 첫 전진량은 첫 슬롯(20pt), 그 뒤는 줄어든 슬롯(14pt)이다.
            expect(gaps[0]).to(beCloseTo(20.0, within: 0.01))
            expect(Array(gaps.dropFirst())).to(
                beCloseTo(Array(repeating: 14.0, count: gaps.count - 1), within: 0.01)
            )
        }

        /// 같은 문단은 **청크를 어떻게 나눠도** 같은 자리에 그려져야 한다 — `maxLineFrames`는
        /// 문자 예산이라 작은 값이 청크를 쪼갠다. 균일한 문단은 청크마다 CT 첫 줄 슬롯 특례를
        /// 새로 타므로, 그 특례가 전진량에 새면 경계마다 자리가 밀린다.
        func testChunkBudgetDoesNotMoveAUniformParagraph() {
            let string = LineBoxFixtures.uniformParagraph(specs: [(.minimumLineHeight, 15)])
            let whole = HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: 100),
                lineWidth: LineBoxFixtures.paragraphWidth
            ).map(\.baselineOrigin.y)
            for budget in [20, 40, 80] {
                let chunked = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: CGPoint(x: 0, y: 100),
                    lineWidth: LineBoxFixtures.paragraphWidth, maxLineFrames: budget
                ).map(\.baselineOrigin.y)
                expect(chunked.count).to(equal(whole.count), description: "예산 \(budget)")
                guard chunked.count == whole.count else { continue }
                expect(chunked.map(Double.init)).to(
                    beCloseTo(whole.map(Double.init), within: 0.01), description: "예산 \(budget)"
                )
            }
        }

        // **문단 간격은 상자 사이에 남는다.** CT는 문단 아래·위 간격을 다음 줄 슬롯의
        // ascent 안에 넣으므로 (실측: 간격 6+4를 준 둘째 문단 첫 줄의 배치 ascent가
        // 9.70 → 19.70) 배치 ascent 복원에서 걷어내야 한다. 걷어내지 않으면 간격이 사라져
        // 둘째 문단이 그만큼 올라간다 — 한글은 줄 간격 여분을 상자 아래 `lineSpacing`으로
        // 적고 다음 상자를 그 아래에 둔다.
    }
#endif
