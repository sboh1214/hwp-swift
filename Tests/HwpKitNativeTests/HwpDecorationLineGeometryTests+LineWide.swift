import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 밑줄의 **줄 단위** 기준 (#226) — 한글 문서·한글 2007 호환 문서에서 글자 아래·위 밑줄과
/// 변경 추적 삽입 밑줄의 자리는 그 줄 상자(한글 줄 캐시의 `vertsize`)의 바닥·상단이고,
/// 두께와 선 모양 축척은 줄 **글자**의 기본 크기 최댓값이다. 취소선은 run 단위라, 밑줄을 단
/// 10pt run에 취소선(자홍)을 함께 걸어 두면 그 줄의 베이스라인 위 0.35 × 10pt에 남아 밑줄
/// (청록)과의 행 간격이 곧 밑줄 자리가 된다 — 베이스라인을 따로 찾지 않고 한 래스터 안에서
/// 잰다.
///
/// 오라클은 한글.app 12.30.0 build 6446의 PDF 내보내기다 (2026-09-22·25, `CharShape` HWPX
/// 기반 합성 문서에서 `hp:linesegarray`를 지워 한글이 새로 조판하게 했다). 10pt 밑줄 run과
/// 한 줄에 무엇이 있는가:
///
/// | 같은 줄 | 아래 밑줄 | 위 밑줄 | 두께 |
/// | --- | ---: | ---: | ---: |
/// | 40pt 무장식 글자·40pt 공백 | −6.84 | — | 1.56 |
/// | 40pt 문단 끝 글자 | −6.24 | +34.20 | 0.36 |
/// | 40pt 한 줄 끝(코드 10) | −6.12 | +34.20 | 0.36 |
/// | 40pt 글자 모양 책갈피 | −6.12 | +34.20 | 0.36 |
/// | 높이 40pt 글자처럼 취급 그림·표 | −6.24 | +34.20 | 0.36 |
/// | 기본 40pt·상대 크기 50% (그 run 자신) | −6.84 | +34.80 | 1.56 |
///
/// 한글 2007 호환 문서는 같은 자리에 고정 0.36pt(−6.12·+34.08~34.20)다. 종전 렌더는 run마다
/// 그 run 글꼴 크기(−1.70·+8.70·0.40)로 그렸다.
///
/// `extension`에 두는 이유는 `+Script`와 같다 (`type_body_length`). 래스터 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let lineWideCyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
    private static let lineWideMagenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
    private static let hwp200XTarget = NSNumber(
        value: HwpCompatibleDocumentTarget.hwp200X.rawValue
    )

    private static func isLineWideCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    private static func isLineWideMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    /// 장식 run — `size`는 run 글꼴 크기, `base`는 글자 모양 기본 크기(없으면 `size`).
    /// 밑줄 종류(`line`)는 청록, 취소선 기준선은 자홍이다.
    private func decoratedRun(
        _ line: NSAttributedString.Key?, size: CGFloat = 10, base: CGFloat? = nil,
        strikethrough: Bool = true, target: NSNumber? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes = plainRun(size: size, base: base, target: target)
        if line == HwpAttributedStringKey.trackInsertUnderline {
            attributes[HwpAttributedStringKey.trackInsertUnderline] = Self.lineWideCyan
        } else if let line {
            attributes[line] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = Self.lineWideCyan
        }
        if strikethrough {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = Self.lineWideMagenta
        }
        return attributes
    }

    /// 장식 없는 run — 조판이 싣는 크기 키(`spaceTargetSize`·`baseFontSize`)를 함께 싣는다.
    private func plainRun(
        size: CGFloat, base: CGFloat? = nil, target: NSNumber? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                "Menlo" as CFString, size, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(base ?? size)),
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = target
        }
        return attributes
    }

    /// 글자처럼 취급 개체·책갈피 같은 마커 run — 높이 `height`(0이면 줄 공간을 예약하지 않는
    /// 마커)·폭 `width`의 run delegate에 글자 모양 크기 `size`를 싣는다.
    private func markerRun(
        height: CGFloat, width: CGFloat, size: CGFloat
    ) throws -> NSAttributedString {
        let extent = UnsafeMutablePointer<CGSize>.allocate(capacity: 1)
        extent.initialize(to: CGSize(width: width, height: height))
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in pointer.assumingMemoryBound(to: CGSize.self).deallocate() },
            getAscent: { pointer in pointer.assumingMemoryBound(to: CGSize.self).pointee.height },
            getDescent: { _ in 0 },
            getWidth: { pointer in pointer.assumingMemoryBound(to: CGSize.self).pointee.width }
        )
        let delegate = try XCTUnwrap(CTRunDelegateCreate(&callbacks, extent))
        var attributes = plainRun(size: size)
        attributes[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    /// 청록 선(밑줄)과 자홍 선(같은 run의 취소선)의 행 중심 간격(pt, 밑줄이 아래면 양수)과
    /// 청록 선의 두께. 줄이 여럿이면 첫 줄의 두 선을 쓴다.
    private func underlineGap(
        _ text: NSAttributedString
    ) throws -> (gap: CGFloat, thickness: CGFloat) {
        let raster = try render(text: text)
        let underline = try XCTUnwrap(
            Self.rowBands(raster, where: Self.isLineWideCyan).first, "밑줄"
        )
        let strike = try XCTUnwrap(
            Self.rowBands(raster, where: Self.isLineWideMagenta).first, "취소선"
        )
        let thickness = try XCTUnwrap(Self.lineThickness(raster) { red, _, _ in red }, "밑줄 두께")
        return (underline - strike, thickness)
    }

    private func line(_ runs: [NSAttributedString]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        runs.forEach(text.append)
        return text
    }

    /// 10pt 밑줄 + 40pt 무장식 글자 한 줄 — 밑줄은 40pt 상자 바닥 아래(−6.8pt)에 40pt 두께
    /// (1.6pt)다. 같은 run의 취소선은 +3.5pt라 간격 10.3pt (종전 run 단위 5.2pt).
    func testUnderlineFollowsTheTallestTextOnTheLine() throws {
        let measured = try underlineGap(line([
            NSAttributedString(
                string: "    ", attributes: decoratedRun(HwpAttributedStringKey.underlineStyle)
            ),
            NSAttributedString(string: "  ", attributes: plainRun(size: 40)),
        ]))
        expect(measured.gap).to(beCloseTo(3.5 + 6.8, within: 0.2))
        expect(measured.thickness).to(beCloseTo(1.6, within: 0.05))
    }

    /// 문단 끝 글자·한 줄 끝·높이 0 마커(책갈피)·글자처럼 취급 개체는 줄 상자에는 들고
    /// **두께 기준에는 들지 않는다** — 40pt인 그것들과 한 줄인 10pt 밑줄은 40pt 상자 바닥 아래
    /// −(6 + 0.2)pt에 10pt 두께 0.4pt다 (한글: −6.12~−6.24·0.36).
    func testLineBoxOnlyMembersMoveTheUnderlineButNotItsThickness() throws {
        let underline = NSAttributedString(
            string: "    ", attributes: decoratedRun(HwpAttributedStringKey.underlineStyle)
        )
        var withEnd = decoratedRun(HwpAttributedStringKey.underlineStyle)
        withEnd[HwpAttributedStringKey.paragraphEndBaseFontSize] = NSNumber(value: 40)
        var lineBreak = plainRun(size: 40)
        lineBreak[HwpAttributedStringKey.lineBreak] = NSNumber(value: true)
        let cases: [(String, NSAttributedString)] = try [
            ("문단 끝 글자", NSAttributedString(string: "    ", attributes: withEnd)),
            ("한 줄 끝", line([
                underline, NSAttributedString(string: "\n", attributes: lineBreak),
                // 다음 줄은 잉크 없는 빈칸 — 글자가 있으면 밑줄 열의 두께 측정을 오염시킨다.
                NSAttributedString(string: "    ", attributes: plainRun(size: 10)),
            ])),
            ("책갈피", line([underline, markerRun(height: 0, width: 0, size: 40), underline])),
            ("개체", line([underline, markerRun(height: 40, width: 20, size: 10), underline])),
        ]
        for (name, text) in cases {
            let measured = try underlineGap(text)
            expect(measured.gap).to(beCloseTo(3.5 + 6.2, within: 0.2), description: name)
            expect(measured.thickness).to(beCloseTo(0.4, within: 0.05), description: name)
        }
    }

    /// 글자 위 밑줄도 줄 단위다 — 40pt 무장식 글자와 한 줄이면 40pt 상자 상단 위(+34.8pt),
    /// 40pt 문단 끝 글자와 한 줄이면 +34.2pt·10pt 두께다. 취소선(+3.5pt)과의 간격으로 잰다.
    func testAboveUnderlineFollowsTheLineBoxTop() throws {
        let above = decoratedRun(HwpAttributedStringKey.underlineAboveStyle)
        let mixed = try underlineGap(line([
            NSAttributedString(string: "    ", attributes: above),
            NSAttributedString(string: "  ", attributes: plainRun(size: 40)),
        ]))
        expect(-mixed.gap).to(beCloseTo(CGFloat(34.8 - 3.5), within: 0.2))
        expect(mixed.thickness).to(beCloseTo(1.6, within: 0.05))
        var withEnd = above
        withEnd[HwpAttributedStringKey.paragraphEndBaseFontSize] = NSNumber(value: 40)
        let ended = try underlineGap(NSAttributedString(string: "    ", attributes: withEnd))
        expect(-ended.gap).to(beCloseTo(CGFloat(34.2 - 3.5), within: 0.2))
        expect(ended.thickness).to(beCloseTo(0.4, within: 0.05))
    }

    /// 변경 추적 삽입 밑줄도 같은 줄 단위다 (한글: 40pt 글자와 한 줄인 10pt 삽입 밑줄이 40pt
    /// 자리·두께 — 0.8배 축소 쪽에서 −5.40pt·1.20pt).
    func testTrackInsertUnderlineFollowsTheLine() throws {
        let measured = try underlineGap(line([
            NSAttributedString(
                string: "    ",
                attributes: decoratedRun(HwpAttributedStringKey.trackInsertUnderline)
            ),
            NSAttributedString(string: "  ", attributes: plainRun(size: 40)),
        ]))
        expect(measured.gap).to(beCloseTo(3.5 + 6.8, within: 0.2))
        expect(measured.thickness).to(beCloseTo(1.6, within: 0.05))
    }

    /// 상대 크기로 줄어든 run도 **글자 모양 기본 크기**로 그린다 — 기본 40pt·상대 크기 50%
    /// (글꼴 20pt) run의 밑줄은 −6.8pt·1.6pt, 취소선은 +14.0pt라 간격 20.8pt다 (한글: −6.84·
    /// +14.04·1.56). 종전에는 20pt 기준(−3.4·+7.0·0.8)이었다.
    func testRelativeSizedRunUsesTheCharShapeBaseSize() throws {
        let measured = try underlineGap(NSAttributedString(
            string: "    ",
            attributes: decoratedRun(HwpAttributedStringKey.underlineStyle, size: 20, base: 40)
        ))
        expect(measured.gap).to(beCloseTo(14 + 6.8, within: 0.2))
        expect(measured.thickness).to(beCloseTo(1.6, within: 0.05))
        // 취소선 두께도 기본 크기 몫이다.
        let raster = try render(text: NSAttributedString(
            string: "    ",
            attributes: decoratedRun(nil, size: 20, base: 40)
        ))
        expect(Self.lineThickness(raster) { _, green, _ in green })
            .to(beCloseTo(1.6, within: 0.05))
    }

    /// 한 문단이 여러 줄로 접히면 줄마다 따로다 — 10pt 밑줄 글만 있는 첫 줄은 −1.7pt, 끝에
    /// 40pt 글자가 든 마지막 줄만 −6.8pt다 (한글: −1.68 / −6.72).
    func testWrappedParagraphDecidesEachLineSeparately() throws {
        let text = line([
            NSAttributedString(
                string: String(repeating: "AAAA ", count: 9),
                attributes: decoratedRun(HwpAttributedStringKey.underlineStyle)
            ),
            NSAttributedString(string: "BB", attributes: plainRun(size: 40)),
        ])
        let raster = try render(text: text)
        let underlines = Self.rowBands(raster, where: Self.isLineWideCyan)
        let strikes = Self.rowBands(raster, where: Self.isLineWideMagenta)
        expect(underlines.count) == 2
        expect(strikes.count) == 2
        guard underlines.count == 2, strikes.count == 2 else { return }
        expect(underlines[0] - strikes[0]).to(beCloseTo(3.5 + 1.7, within: 0.2))
        expect(underlines[1] - strikes[1]).to(beCloseTo(3.5 + 6.8, within: 0.2))
    }

    /// 한글 2007 호환 문서도 같은 줄 상자 바닥에 고정 0.36pt 선을 얹는다 — 40pt 글자와 한 줄인
    /// 10pt 밑줄은 −(6 + 0.18)pt (한글: −6.12). 종전 run 단위는 −1.68pt였다.
    func testHwp2007UnderlineFollowsTheLineBox() throws {
        let measured = try underlineGap(line([
            NSAttributedString(
                string: "    ",
                attributes: decoratedRun(
                    HwpAttributedStringKey.underlineStyle, target: Self.hwp200XTarget
                )
            ),
            NSAttributedString(
                string: "  ", attributes: plainRun(size: 40, target: Self.hwp200XTarget)
            ),
        ]))
        expect(measured.gap).to(beCloseTo(3.5 + 6.18, within: 0.2))
        expect(measured.thickness).to(beCloseTo(0.36, within: 0.06))
    }

    /// 밑줄 선 모양의 축척도 줄 글자 기준 크기다 — 40pt 글자와 한 줄인 10pt 긴 점선은 40pt
    /// 몫 패턴(단위 0.057 × 40 = 2.28pt, 주기 8단위 18.24pt)으로 그려진다 (한글: 선 11.40pt·공백
    /// 6.96pt). 10pt 몫이면 주기 4.56pt다.
    func testShapedUnderlineScalesWithTheLineText() throws {
        var dotted = decoratedRun(HwpAttributedStringKey.underlineStyle, strikethrough: false)
        dotted[HwpAttributedStringKey.underlineShape] = NSNumber(
            value: HwpBorderType.longDotLine.rawValue
        )
        dotted[HwpAttributedStringKey.charShapeId] = NSNumber(value: 1)
        var big = plainRun(size: 40)
        big[HwpAttributedStringKey.charShapeId] = NSNumber(value: 2)
        let raster = try render(text: line([
            NSAttributedString(string: String(repeating: "A", count: 20), attributes: dotted),
            NSAttributedString(string: " ", attributes: big),
        ]))
        let center = try XCTUnwrap(Self.rowCenter(raster, where: Self.isLineWideCyan), "점선")
        let rows = Int((center - 0.6) * Self.scale) ... Int((center + 0.6) * Self.scale)
        let columns = (0 ..< raster.pixelWidth).map { x in
            rows.contains { y in
                let offset = y * raster.bytesPerRow + x * 4
                return Self.isLineWideCyan(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
            }
        }
        var starts: [CGFloat] = []
        for (index, ink) in columns.enumerated() where ink && (index == 0 || !columns[index - 1]) {
            starts.append(CGFloat(index) / Self.scale)
        }
        expect(starts.count) >= 3
        guard starts.count >= 3 else { return }
        let period: CGFloat = 0.057 * 40 * 8
        expect(starts[1] - starts[0]).to(beCloseTo(period, within: 0.2))
        expect(starts[2] - starts[1]).to(beCloseTo(period, within: 0.2))
    }

    /// 긴 점선 한 줄의 잉크가 시작하는 x (pt) 목록 — `band`(pt) 행들에서 조건 색 열을 본다.
    private func lineWideInkStarts(
        _ raster: Raster, band: ClosedRange<CGFloat>,
        where match: (UInt8, UInt8, UInt8) -> Bool
    ) -> [CGFloat] {
        let rows = Int(band.lowerBound * Self.scale) ... Int(band.upperBound * Self.scale)
        let columns = (0 ..< raster.pixelWidth).map { x in
            rows.contains { y in
                let offset = y * raster.bytesPerRow + x * 4
                return match(raster.data[offset], raster.data[offset + 1], raster.data[offset + 2])
            }
        }
        var starts: [CGFloat] = []
        for (index, ink) in columns.enumerated() where ink && (index == 0 || !columns[index - 1]) {
            starts.append(CGFloat(index) / Self.scale)
        }
        return starts
    }

    /// 한 글자 모양 안에서 슬롯 상대 크기가 달라 CoreText가 run을 갈라도 긴 점선의 위상은
    /// 이어진다 — 축척이 기본 크기라 두 run이 같은 패턴이다 (#226, 한글 12.30 실측 2026-09-26:
    /// 기본 20pt·한글 슬롯 50%·라틴 100% "가나다라 abcdefg 마바사아"의 긴 점선 밑줄이 주기
    /// 9.0pt로 슬롯 경계를 넘어 이어진다). 종전에는 `spaceTargetSize`가 묶음을 갈라 경계에서
    /// 패턴이 다시 시작했다.
    func testDottedPatternContinuesAcrossSlotRelativeSizes() throws {
        func slot(size: CGFloat) -> [NSAttributedString.Key: Any] {
            var attributes = decoratedRun(
                HwpAttributedStringKey.underlineStyle, size: size, base: 20, strikethrough: false
            )
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(
                value: HwpBorderType.longDotLine.rawValue
            )
            attributes[HwpAttributedStringKey.charShapeId] = NSNumber(value: 7)
            return attributes
        }
        let first = NSAttributedString(string: "AAAA", attributes: slot(size: 20))
        let text = line([first, NSAttributedString(string: "AAAAAAAA", attributes: slot(size: 10))])
        let boundary = 10 + CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(first), nil, nil, nil
        )
        let raster = try render(text: text)
        let center = try XCTUnwrap(Self.rowCenter(raster, where: Self.isLineWideCyan), "점선")
        let starts = lineWideInkStarts(
            raster, band: (center - 0.4) ... (center + 0.4), where: Self.isLineWideCyan
        )
        // 기본 20pt 몫 주기 0.057 × 20 × 8 = 9.12pt가 run 시작(x 10)부터 경계(x 58.16)를 넘어
        // 끊기지 않는다. 경계는 여섯째 선(55.6~61.3) 한가운데라 다시 시작한 무늬는 경계의 새
        // 선이 앞 선과 붙어 잉크 시작이 안 생기고, 일곱째 시작이 64.72가 아니라 67.3으로 밀린다
        // — 경계 뒤 시작들이 가른다.
        let period: CGFloat = 0.057 * 20 * 8
        expect(boundary).to(beCloseTo(58.16, within: 0.3))
        expect(starts.count) >= 10
        for (index, start) in starts.prefix(10).enumerated() {
            expect(start).to(beCloseTo(10 + period * CGFloat(index), within: 0.3))
        }
    }

    /// 2중선·물결 밑줄의 띠도 줄 글자 기준 크기다 — 40pt 무장식 글자와 한 줄인 10pt 2중선은
    /// 띠 0.12 × 40 = 4.8pt를 [1/4·1/2·1/4]로 나눈 두 선(베이스라인 아래 6.6·10.2pt, 굵기 1.2pt),
    /// 물결은 진폭 0.112 × 40 + 획 0.03 × 40 = 5.68pt 폭이다 (한글 12.30: 2중선 −6.48·−10.08·
    /// 1.20pt, 물결 진폭 4.56·획 1.20pt). 선 모양 축척만 10pt 몫으로 되돌리면 두 선이 6.15·
    /// 7.05pt(띠 1.2pt)·물결 폭 1.42pt이고, 종전 run 단위(자리까지 10pt)면 1.65·2.55pt였다.
    /// 줄 상자만 큰 줄(L > T)은 `testShapedUnderlineIgnoresLineBoxOnlyMembers`가 본다.
    func testDoubleAndWaveUnderlinesScaleWithTheLineText() throws {
        func shaped(_ shape: HwpBorderType) throws -> Raster {
            var attributes = decoratedRun(HwpAttributedStringKey.underlineStyle)
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(value: shape.rawValue)
            attributes[HwpAttributedStringKey.charShapeId] = NSNumber(value: 1)
            var big = plainRun(size: 40)
            big[HwpAttributedStringKey.charShapeId] = NSNumber(value: 2)
            return try render(text: line([
                NSAttributedString(string: "        ", attributes: attributes),
                NSAttributedString(string: " ", attributes: big),
            ]))
        }
        let double = try shaped(.doubleLine)
        let strike = try XCTUnwrap(
            Self.rowBands(double, where: Self.isLineWideMagenta).first, "취소선"
        )
        let bands = Self.rowBands(double, where: Self.isLineWideCyan)
        expect(bands.count) == 2
        guard bands.count == 2 else { return }
        expect(bands[0] - strike).to(beCloseTo(3.5 + 6.6, within: 0.25))
        expect(bands[1] - strike).to(beCloseTo(3.5 + 10.2, within: 0.25))
        let wave = try shaped(.wave)
        var rows: [Int] = []
        for y in 0 ..< wave.pixelHeight {
            let hit = (0 ..< wave.pixelWidth).contains { x in
                let offset = y * wave.bytesPerRow + x * 4
                return Self.isLineWideCyan(
                    wave.data[offset], wave.data[offset + 1], wave.data[offset + 2]
                )
            }
            if hit {
                rows.append(y)
            }
        }
        let extent = CGFloat((rows.last ?? 0) - (rows.first ?? 0) + 1) / Self.scale
        expect(extent).to(beCloseTo(CGFloat((0.112 + 0.03) * 40), within: 0.6))
    }

    /// 상대 크기로 줄어든 run의 선 모양 취소선도 글자 모양 기본 크기 몫이다 — 기본 40pt·상대 크기
    /// 50%(글꼴 20pt) run의 긴 점선 취소선은 한 토막 5 × 0.057 × 40 = 11.4pt·주기 18.24pt
    /// (한글 12.30 실측 2026-09-26: 11.40pt·18.36pt, 물결 취소선도 40pt 몫 진폭 4.56pt). 종전
    /// `spaceTargetSize` 축척이면 20pt 몫 5.7·9.12pt다.
    func testShapedStrikethroughUsesTheCharShapeBaseSize() throws {
        var attributes = decoratedRun(nil, size: 20, base: 40)
        attributes[HwpAttributedStringKey.strikethroughShape] = NSNumber(
            value: HwpBorderType.longDotLine.rawValue
        )
        attributes[HwpAttributedStringKey.charShapeId] = NSNumber(value: 1)
        let raster = try render(text: NSAttributedString(
            string: String(repeating: "A", count: 16), attributes: attributes
        ))
        let center = try XCTUnwrap(Self.rowCenter(raster, where: Self.isLineWideMagenta), "취소선")
        let starts = lineWideInkStarts(
            raster, band: (center - 0.5) ... (center + 0.5), where: Self.isLineWideMagenta
        )
        expect(starts.count) >= 3
        guard starts.count >= 3 else { return }
        let period = CGFloat(0.057 * 40 * 8)
        expect(starts[1] - starts[0]).to(beCloseTo(period, within: 0.3))
        expect(starts[2] - starts[1]).to(beCloseTo(period, within: 0.3))
    }

    /// 선 모양 축척은 줄 **상자**(L)가 아니라 줄 **글자**(T) 몫이다 — 40pt 문단 끝 글자와 한
    /// 줄인 10pt 긴 점선은 자리는 40pt 상자 바닥(−6.2pt)이지만 무늬는 10pt 몫(주기 4.56pt)이고,
    /// 2중선은 그 가장자리 6.0pt에서 10pt 몫 띠 1.2pt(두 선 6.15·7.05pt)다 (한글 12.30 S18: 자리
    /// −6.24pt·선 2.88·공백 1.68pt). L로 재면 주기 18.24pt·두 선 6.6·10.2pt가 된다.
    func testShapedUnderlineIgnoresLineBoxOnlyMembers() throws {
        func shaped(_ shape: HwpBorderType) throws -> Raster {
            var attributes = decoratedRun(HwpAttributedStringKey.underlineStyle)
            attributes[HwpAttributedStringKey.underlineShape] = NSNumber(value: shape.rawValue)
            attributes[HwpAttributedStringKey.charShapeId] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.paragraphEndBaseFontSize] = NSNumber(value: 40)
            return try render(text: NSAttributedString(
                string: String(repeating: " ", count: 16), attributes: attributes
            ))
        }
        let dotted = try shaped(.longDotLine)
        let center = try XCTUnwrap(Self.rowCenter(dotted, where: Self.isLineWideCyan), "점선")
        let starts = lineWideInkStarts(
            dotted, band: (center - 0.4) ... (center + 0.4), where: Self.isLineWideCyan
        )
        expect(starts.count) >= 3
        guard starts.count >= 3 else { return }
        let period = CGFloat(0.057 * 10 * 8)
        expect(starts[1] - starts[0]).to(beCloseTo(period, within: 0.2))
        expect(starts[2] - starts[1]).to(beCloseTo(period, within: 0.2))
        let double = try shaped(.doubleLine)
        let strike = try XCTUnwrap(
            Self.rowBands(double, where: Self.isLineWideMagenta).first, "취소선"
        )
        let bands = Self.rowBands(double, where: Self.isLineWideCyan)
        expect(bands.count) == 2
        guard bands.count == 2 else { return }
        expect(bands[0] - strike).to(beCloseTo(3.5 + 6.15, within: 0.25))
        expect(bands[1] - strike).to(beCloseTo(3.5 + 7.05, within: 0.25))
    }
}
