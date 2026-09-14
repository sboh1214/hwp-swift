import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// 글자 장식 선의 **실물 픽스처 핀** (#136, #176) — 취소선·글자 위/아래 밑줄·
/// 변경 추적 표시선이 쪽의 어느 자리에 떨어지는지, 그리고 HWP와 HWPX 저장본이
/// 같은 자리에 그려지는지를 잠근다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-08 실측, 벡터 좌표):
/// `CharShape` 쌍의 청록 취소선은 두 포맷 모두 베이스라인 위 3.60pt(0.36em,
/// 장치 0.12pt 양자화 포함 0.35em)에 두께 0.36pt로 한 줄만 그려진다 —
/// **한글도 두 포맷을 같은 자리에 그린다**. 이슈 본문의 "한글이 .hwp는 아래
/// 단선, .hwpx는 가운데로 그린다"는 관측은 재현되지 않았다.
///
/// 여기 핀은 **한글 실물의 쪽 좌표**(위에서부터 pt)다 — 줄 캐시가 적어 둔 베이스라인
/// (`lineLocation + baselineDistance`, #178)에 실측 비율을 더한 값이고, 래스터 양자화
/// (0.25pt)와 잉크 가중 중심의 잔차만 허용 오차로 둔다. 비율 자체는
/// `HwpDecorationLineGeometryTests`가 폰트 독립으로 잡는다. 폰트는
/// `HwpFontResolver.testDeterministic`이라 기기 독립이다.
final class FixtureDecorationLineRenderTests: XCTestCase {
    private static let scale: CGFloat = 4

    private struct Raster {
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int
        let data: [UInt8]

        func matches(_ y: Int, _ match: (UInt8, UInt8, UInt8) -> Bool) -> Int {
            var count = 0
            for x in 0 ..< pixelWidth {
                let offset = y * bytesPerRow + x * 4
                if match(data[offset], data[offset + 1], data[offset + 2]) {
                    count += 1
                }
            }
            return count
        }

        /// 한 행에서 조건에 맞는 픽셀이 가로로 이어진 최대 길이 (px).
        func longestRun(_ y: Int, where match: (UInt8, UInt8, UInt8) -> Bool) -> Int {
            var best = 0
            var run = 0
            for x in 0 ..< pixelWidth {
                let offset = y * bytesPerRow + x * 4
                if match(data[offset], data[offset + 1], data[offset + 2]) {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
            }
            return best
        }

        /// 조건에 맞는 픽셀이 3개를 넘는 행들의 잉크 가중 중심 (pt, 위에서부터).
        /// `range`(pt)를 주면 그 구간 안에서만 찾는다.
        func center(
            in range: ClosedRange<CGFloat>? = nil,
            where match: (UInt8, UInt8, UInt8) -> Bool
        ) -> CGFloat? {
            var weighted = 0.0
            var total = 0.0
            for y in 0 ..< pixelHeight {
                let point = (CGFloat(y) + 0.5) / FixtureDecorationLineRenderTests.scale
                if let range, !range.contains(point) {
                    continue
                }
                let count = matches(y, match)
                guard count > 3 else { continue }
                weighted += Double(point) * Double(count)
                total += Double(count)
            }
            return total > 0 ? CGFloat(weighted / total) : nil
        }

        /// 조건에 맞는 행들의 위·아래 끝 (pt).
        func band(
            in range: ClosedRange<CGFloat>? = nil,
            where match: (UInt8, UInt8, UInt8) -> Bool
        ) -> (top: CGFloat, bottom: CGFloat)? {
            var top: CGFloat?
            var bottom: CGFloat?
            for y in 0 ..< pixelHeight {
                let point = (CGFloat(y) + 0.5) / FixtureDecorationLineRenderTests.scale
                if let range, !range.contains(point) {
                    continue
                }
                guard matches(y, match) > 3 else { continue }
                if top == nil {
                    top = point
                }
                bottom = point
            }
            guard let top, let bottom else { return nil }
            return (top, bottom)
        }
    }

    private static func raster(_ id: String, hwpx: Bool) async throws -> Raster {
        let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
            .appendingPathComponent(id)
            .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: url)
        let page = try XCTUnwrap(document.pages.first)
        let pixelWidth = Int(page.size.width * scale)
        let pixelHeight = Int(page.size.height * scale)
        let image = try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: document.imageStore,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            unresolvedImages: .fail
        )
        // 픽셀 버퍼는 CGContext가 소유하게 둔다 (`data: nil`) — Array의
        // `withUnsafeMutableBytes` 포인터는 클로저 안에서만 유효해서, 그 포인터로
        // 만든 컨텍스트에 밖에서 그리면 미정의 동작이다.
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        )
        // 행 보폭은 CG가 정렬에 맞춰 정하므로 되읽어 쓴다.
        let bytesPerRow = context.bytesPerRow
        let pixels = try XCTUnwrap(context.data)
        let data = [UInt8](UnsafeRawBufferPointer(
            start: pixels, count: bytesPerRow * pixelHeight
        ))
        return Raster(
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            bytesPerRow: bytesPerRow, data: data
        )
    }

    private static func isCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    private static func isDark(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 110 && green < 110 && blue < 110
    }

    private static func isRed(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 130 && green < 90 && blue < 90
    }

    private static func isGreen(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue < 100
    }

    /// `CharShape` 쌍의 "취소선 색 #00ffff" 줄 — 두 포맷이 같은 행에 한 줄만
    /// 그리고, 그 선이 글자 잉크의 세로 가운데를 지난다 (한글 실물의 성질).
    func testStrikethroughCrossesGlyphCenterIdenticallyInBothFormats() async throws {
        var centers: [CGFloat] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster("CharShape", hwpx: hwpx)
            let center = try XCTUnwrap(
                raster.center(where: Self.isCyan), "\(format): 취소선을 못 찾았다"
            )
            centers.append(center)

            // 같은 줄의 글자 잉크 (선 위아래 6pt 안). 취소선이 그 띠의 세로
            // 가운데를 지나야 "글자 가운데"다 — 종전 산식(x-height 절반)은
            // 0.85pt 아래였다.
            let ink = try XCTUnwrap(
                raster.band(in: (center - 6) ... (center + 6), where: Self.isDark),
                "\(format): 글자 잉크를 못 찾았다"
            )
            let inkCenter = (ink.top + ink.bottom) / 2
            expect(abs(center - inkCenter)).to(
                beLessThan(0.6), description: "\(format) 선 \(center) 잉크중심 \(inkCenter)"
            )
        }
        expect(centers[0]).to(
            beCloseTo(centers[1], within: 0.01), description: "HWP와 HWPX가 같은 자리"
        )
        // 한글 실물의 쪽 좌표 핀 (위에서부터 pt) — 이 줄의 베이스라인은 한글 줄
        // 캐시가 283.7pt(본문 상단 99.2 + vertpos 176.0 + baseline 8.5)로 적어 두었고
        // 취소선은 그 위 0.35em이다. #178 전에는 우리 렌더가 281.7이었다.
        expect(centers[0]).to(beCloseTo(280.2, within: 0.2))
    }

    /// `CharShape` 쌍의 "밑줄 색 #00ff00" 줄 — 밑줄 '글자 아래'가 두 포맷에서 같은
    /// 행에 한 줄 그려지고, 그 선이 글자 잉크 **아래**에 놓인다 (#176). 한글 실물은
    /// 베이스라인 아래 0.17em이라 10pt에서 1.7pt다 — 종전 0.20em(2.0pt)은 그보다
    /// 0.3pt 낮았고 두께는 0.4pt 고정이었다.
    func testBelowUnderlineSitsUnderGlyphsIdenticallyInBothFormats() async throws {
        var centers: [CGFloat] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster("CharShape", hwpx: hwpx)
            let center = try XCTUnwrap(
                raster.center(where: Self.isGreen), "\(format): 밑줄을 못 찾았다"
            )
            centers.append(center)

            // 같은 줄의 글자 잉크 (선 위 12pt ~ 아래 6pt — 다음 줄 글자보다 안쪽).
            // 밑줄은 잉크 바닥보다 아래여야 한다 — 폰트 underlinePosition(−0.075em)
            // 으로 그리면 잉크를 관통해 띠의 바닥이 선 아래로 내려간다.
            let ink = try XCTUnwrap(
                raster.band(in: (center - 12) ... (center + 6), where: Self.isDark),
                "\(format): 글자 잉크를 못 찾았다"
            )
            expect(ink.bottom).to(
                beLessThan(center), description: "\(format): 선이 글자보다 아래"
            )
            // 선 두께: 10pt × 0.04 = 0.4pt = 1.6px — `isGreen`(커버리지 ≥ ~0.6)을
            // 통과하는 행은 1~2행이다. 3행(0.5pt) 이상이면 두께 산식이 틀어진 것.
            let band = try XCTUnwrap(
                raster.band(in: (center - 1) ... (center + 1), where: Self.isGreen),
                "\(format): 밑줄 띠를 못 찾았다"
            )
            expect(band.bottom - band.top).to(beLessThan(0.5), description: "\(format) 두께")
        }
        expect(centers[0]).to(
            beCloseTo(centers[1], within: 0.01), description: "HWP와 HWPX가 같은 자리"
        )
        // 한글 실물의 쪽 좌표 핀 (위에서부터 pt) — 베이스라인 235.7(줄 캐시:
        // 99.2 + 128.0 + 8.5) + 1.7이다. #178 전에는 베이스라인 격차 1.6pt가 얹혀
        // 239.1이었다.
        expect(centers[0]).to(beCloseTo(237.4, within: 0.2))
    }

    /// `underline-above` 쌍 — 밑줄 종류 3(글자 위)을 실제로 그린다. 선은 글자
    /// 잉크보다 위에 있고 두 포맷이 같은 행이다.
    func testAboveUnderlineIsDrawnAboveGlyphsInBothFormats() async throws {
        var centers: [CGFloat] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster("underline-above", hwpx: hwpx)
            // 밑줄은 문단 전폭이라 어느 글자 행보다 검정 픽셀이 많다.
            let lineRow = try XCTUnwrap(
                (0 ..< raster.pixelHeight)
                    .map { ($0, raster.matches($0, Self.isDark)) }
                    .max { $0.1 < $1.1 },
                "\(format): 밑줄 행을 못 찾았다"
            )
            let center = (CGFloat(lineRow.0) + 0.5) / Self.scale
            centers.append(center)

            let ink = try XCTUnwrap(
                raster.band(in: (center + 0.6) ... (center + 20), where: Self.isDark),
                "\(format): 글자 잉크를 못 찾았다"
            )
            expect(ink.top).to(
                beGreaterThan(center), description: "\(format): 선이 글자보다 위"
            )
        }
        expect(centers[0]).to(
            beCloseTo(centers[1], within: 0.01), description: "HWP와 HWPX가 같은 자리"
        )
        // 한글 실물: 베이스라인 107.7(줄 캐시: 99.2 + 0 + 8.5) − 8.7 = 99.0pt.
        // 한글 PDF의 텍스트 베이스라인 실측은 107.76이라 99.06이다 (#178).
        // 수정 전에는 100.5로 1.5pt 낮았다.
        expect(centers[0]).to(beCloseTo(99.0, within: 0.3))
    }

    /// `track-changes` — 삭제선(베이스라인 위)과 삽입 밑줄(아래)이 둘 다 빨강
    /// 한 줄씩 있고, 이 문서(MS Word 호환 문서)에서 한글이 그리는 비율(삭제선
    /// +0.29em·삽입 밑줄 −0.26em)로 놓인다. 두 선의 간격이 그 비율의 핀이다.
    func testTrackChangeMarksKeepTheirOwnGeometry() async throws {
        let raster = try await Self.raster("track-changes", hwpx: false)
        // 변경 추적 글자 자체도 빨강이고 왼쪽 여백엔 세로 변경 막대가 있다 —
        // 가로로 길게 이어진 빨강만 선으로 센다 (글리프 획은 그만큼 못 잇는다).
        let rows = (0 ..< raster.pixelHeight)
            .filter { raster.longestRun($0, where: Self.isRed) > Int(20 * Self.scale) }
            .map { (CGFloat($0) + 0.5) / Self.scale }
        // 이어진 행들을 한 선으로 묶어 중심을 낸다.
        var groups: [[CGFloat]] = []
        for row in rows {
            if let last = groups.last?.last, row - last < 0.5 / Self.scale + 0.3 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        expect(groups.count).to(equal(2), description: "삭제선 + 삽입 밑줄 두 줄")
        let strike = groups[0].reduce(0, +) / CGFloat(groups[0].count)
        let insert = groups[1].reduce(0, +) / CGFloat(groups[1].count)
        // 삭제선은 베이스라인 위, 삽입 밑줄은 아래다. 비율 자체는
        // `HwpDecorationLineGeometryTests`가 잡고, 여기서는 실물에서의 간격을
        // 핀한다. 두 비율은 이 픽스처(MS Word 호환 문서)의 값이다 (#176, #187).
        expect(insert).to(beGreaterThan(strike + 1))
        // 10pt 글자: 삭제선 +0.29em(2.9pt) + 삽입 밑줄 −0.26em(2.6pt) = 5.5pt (#176).
        // 종전 삽입 밑줄은 0.75pt 사각형의 아래 모서리가 −3.5pt라 중심이 −3.125pt,
        // 간격 6.0pt였다.
        let expected = (HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio
            + HwpRenderTuning.Text.trackChangeInsertUnderlineCenterRatio) * 10
        expect(insert - strike).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(5.5, within: 0.001))
    }
}
