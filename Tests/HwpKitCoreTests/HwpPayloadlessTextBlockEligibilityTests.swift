import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// payload 없이 텍스트로 그려지는 블록은 종류와 무관하게 같은 자격을 받는다 (#200 리뷰).
    ///
    /// `plainCommands`는 payload 없는 `.text`·`.table`·`.textbox`·`.footnote` 블록을 모두
    /// `block.attributedString`으로 그리는데, 자격은 `.text`에만 `textBounds`를 주고 나머지는
    /// 프레임에서 멈춰 프레임 밖으로 옮겨진 링크 글리프가 스팬 기하 확인 전에 기각됐다.
    /// 방출·선택·자격이 `HwpBlockContentWalker.plainText` 한 술어를 공유한다.
    final class HwpPayloadlessTextBlockEligibilityTests: XCTestCase {
        private static let url = "https://example.com"
        private static let frame = CGRect(x: 0, y: 100, width: 100, height: 10)
        private static let lowered = NSAttributedString(string: "LINK", attributes: [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName("Helvetica" as CFString, 10, nil),
            HwpAttributedStringKey.hyperlink: url,
            HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -8),
        ])

        private func url(of hit: HwpHitResult?) -> String? {
            if case let .hyperlink(url, _) = hit {
                return url
            }
            return nil
        }

        /// 내려간 밴드 하단 1pt 위 — 프레임(y 100…110) 밖이다.
        private var loweredTap: CGPoint {
            let regions = HwpDrawnTextLayout.hyperlinkRegions(
                attributedString: Self.lowered, origin: Self.frame.origin,
                lineWidth: Self.frame.width
            )
            expect(regions.count) == 2
            let band = regions.last?.rect ?? .null
            return CGPoint(x: band.minX + 2, y: band.maxY - 1)
        }

        func testPayloadlessTextRenderedKindsShareTheTextEligibility() {
            let reference = HwpHitTester().hitEligibleFrame(
                for: AnyHwpBlock(frame: Self.frame, kind: .text, attributedString: Self.lowered)
            )
            // 탭이 프레임 밖이어야 자격 차이가 결과를 가른다.
            expect(Self.frame.contains(self.loweredTap)) == false
            expect(reference.contains(self.loweredTap)) == true

            for kind in [HwpBlockKind.table, .textbox, .footnote] {
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: kind, attributedString: Self.lowered
                )
                let page = HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [block], pageNumber: 1
                )
                // 정말 텍스트로 그려지는 블록인지 — 방출이 drawText를 낸다.
                let commands = HwpPaintListBuilder().build(for: page).commands
                expect(commands.contains {
                    if case .drawText = $0 {
                        return true
                    }
                    return false
                }).to(beTrue(), description: "\(kind)")

                expect(HwpHitTester().hitEligibleFrame(for: block))
                    .to(equal(reference), description: "\(kind)")
                expect(self.url(of: HwpHitTester().hit(page: page, point: self.loweredTap)))
                    .to(equal(Self.url), description: "\(kind)")
            }
        }

        /// 블록-레벨 링크의 프레임 밖 폴백(`nonContainerBlockLevelURL`)도 같은 술어를 탄다 —
        /// 텍스트로 그려지는 네 종류는 내려간 글리프 위에서 열리고 빈 띠에서는 안 열리며,
        /// 글자가 없는 종류는 문자열·URL이 실려 있어도 프레임에서 멈춘다.
        func testBlockLevelLinkFallbackFollowsTheSamePredicate() {
            let plain = NSAttributedString(string: "LINK", attributes: [
                kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName("Helvetica" as CFString, 10, nil),
                HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -8),
            ])
            let band = HwpDrawnTextLayout.textLineRegions(
                attributedString: plain, origin: Self.frame.origin, lineWidth: Self.frame.width
            ).last ?? .null
            let onGlyph = CGPoint(x: band.minX + 2, y: band.maxY - 1)
            let emptyBand = CGPoint(x: 80, y: band.maxY - 1)
            expect(Self.frame.contains(onGlyph)) == false

            for kind in [HwpBlockKind.text, .table, .textbox, .footnote] {
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: kind, attributedString: plain, hyperlinkURL: Self.url
                )
                let page = HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [block], pageNumber: 1
                )
                expect(self.url(of: HwpHitTester().hit(page: page, point: onGlyph)))
                    .to(equal(Self.url), description: "\(kind)")
                expect(self.url(of: HwpHitTester().hit(page: page, point: emptyBand)))
                    .to(beNil(), description: "\(kind)")
            }
            for kind in [HwpBlockKind.image, .shape, .placeholder] {
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: kind, attributedString: plain, hyperlinkURL: Self.url
                )
                let page = HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [block], pageNumber: 1
                )
                expect(HwpHitTester().hit(page: page, point: onGlyph))
                    .to(beNil(), description: "\(kind)")
            }
        }

        /// 방출이 `drawText`를 내는 것과 `plainText`가 있는 것은 **동치**다 — 종류 7 × 문자열
        /// (없음·빈·있음), payload 없음. 한쪽 목록만 바뀌면 자격과 페인트가 갈린다.
        func testPaintEmitsTextExactlyWhenPlainTextIsPresent() {
            let kinds: [HwpBlockKind] = [
                .text, .table, .textbox, .footnote, .image, .shape, .placeholder,
            ]
            let strings: [NSAttributedString?] = [nil, NSAttributedString(string: ""), Self.lowered]
            for kind in kinds {
                for string in strings {
                    let block = AnyHwpBlock(frame: Self.frame, kind: kind, attributedString: string)
                    let page = HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [block], pageNumber: 1
                    )
                    let drawn = HwpPaintListBuilder().build(for: page).commands.filter {
                        if case .drawText = $0 {
                            return true
                        }
                        return false
                    }.count
                    let expected = HwpBlockContentWalker.plainText(of: block) == nil ? 0 : 1

                    expect(drawn).to(
                        equal(expected), description: "\(kind) \(string?.string ?? "nil")"
                    )
                }
            }
        }

        /// 텍스트로 그려지지 않는 종류(`.image` 등)는 문자열이 실려도 종전대로 프레임이다 —
        /// 술어가 `walkText`와 같아야 자격만 넓어지는 일이 없다.
        func testNonTextKindsKeepTheFrame() {
            for kind in [HwpBlockKind.image, .shape, .placeholder] {
                let block = AnyHwpBlock(
                    frame: Self.frame, kind: kind, attributedString: Self.lowered
                )
                var visited = 0
                HwpBlockContentWalker.walkText(block: block) { _, _, _ in visited += 1 }

                expect(visited).to(equal(0), description: "\(kind)")
                expect(HwpHitTester().hitEligibleFrame(for: block))
                    .to(equal(Self.frame), description: "\(kind)")
            }
        }
    }
#endif
