import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// MS 워드 호환 문서(#187)의 장식선 — 글꼴 지표(`HwpMsWordLineBox`)에서 나오고, 밑줄은
/// 줄 단위(줄 상자 = run 상자들의 축별 최댓값), 취소선은 run 단위다. 한글 문서의 글자
/// 크기 비례 기하는 본체 파일이 잡는다.
///
/// 오라클은 한글.app 12.30.0의 PDF 내보내기다 (2026-09-15, 글꼴 32종 + 합성 글꼴 7종 ×
/// 10·40·80pt, 혼합 줄 12조합 — `HwpRenderTuning.Text`의 `msWord*` doc-comment). 여기서는
/// Menlo(win 0.9282/0.2358, CJK 비트 → 상자 1.164em)와 Helvetica(그 밖 갈래 → 상자
/// 0.9041em)로 산식을 픽셀로 잰다.
///
/// `extension`에 두는 이유는 `HwpDecorationLineGeometryTests` 본문이 `type_body_length`
/// 경고선에 닿아 있어서다. 래스터·측정 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let msWord = NSNumber(value: HwpCompatibleDocumentTarget.msWord.rawValue)

    private func run(
        _ fontName: String, size: CGFloat, color: CGColor,
        underline: Bool = false, above: Bool = false, strikethrough: Bool = false,
        target: NSNumber? = HwpDecorationLineGeometryTests.msWord
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName(
                fontName as CFString, size, nil
            ),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = target
        }
        if underline {
            attributes[HwpAttributedStringKey.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = color
        }
        if above {
            attributes[HwpAttributedStringKey.underlineAboveStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = color
        }
        if strikethrough {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = color
        }
        return attributes
    }

    private static let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
    private static let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)

    private static func isCyan(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red < 100 && green > 150 && blue > 150
    }

    private static func isMagenta(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        red > 150 && green < 100 && blue > 150
    }

    private func menloBox(_ size: CGFloat) -> HwpMsWordLineBox {
        HwpMsWordLineBox.metrics(of: CTFontCreateWithName("Menlo" as CFString, size, nil))
            .scaled(by: size)
    }

    /// Menlo 20pt 밑줄과 취소선의 간격이 글꼴 지표 산식과 같다 — 밑줄 −(0.2358 + 0.021 ×
    /// 1.164) × 20 = −5.204pt, 취소선 0.273 × 0.9282 × 20 = 5.068pt → 간격 10.27pt (한글
    /// 문서의 0.52em = 10.4pt와 다르다).
    func testMsWordUnderlineAndStrikethroughFollowFontMetrics() throws {
        let size: CGFloat = 20
        let text = NSMutableAttributedString(
            string: "AAAA", attributes: run("Menlo", size: size, color: Self.cyan, underline: true)
        )
        text.append(NSAttributedString(
            string: "BBBB",
            attributes: run("Menlo", size: size, color: Self.magenta, strikethrough: true)
        ))
        let raster = try render(text: text)
        let underline = try XCTUnwrap(Self.rowCenter(raster, where: Self.isCyan), "밑줄")
        let strike = try XCTUnwrap(Self.rowCenter(raster, where: Self.isMagenta), "취소선")
        let box = menloBox(size)
        let expected = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: box, thicknessFontSize: size
        ).center - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box).center
        expect(underline - strike).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(10.272, within: 0.01))
    }

    /// 두께 — 밑줄은 0.05 × cell(Menlo 20pt: 1.164pt), 취소선은 한글 문서와 같은 0.04em
    /// (0.8pt). 빈칸 run 위 선의 열 커버리지 합으로 잰다.
    func testMsWordThicknessComesFromTheCell() throws {
        let size: CGFloat = 20
        let text = NSMutableAttributedString(
            string: "    ", attributes: run("Menlo", size: size, color: Self.cyan, underline: true)
        )
        text.append(NSAttributedString(
            string: "    ",
            attributes: run("Menlo", size: size, color: Self.magenta, strikethrough: true)
        ))
        let raster = try render(text: text)
        let underline = try XCTUnwrap(Self.lineThickness(raster) { red, _, _ in red }, "밑줄 두께")
        let strike = try XCTUnwrap(Self.lineThickness(raster) { _, green, _ in green }, "취소선 두께")
        let box = menloBox(size)
        expect(underline).to(beCloseTo(box.cellHeight * 0.05, within: 0.05))
        expect(box.cellHeight * 0.05).to(beCloseTo(1.164, within: 0.001))
        expect(strike).to(beCloseTo(0.8, within: 0.05))
    }

    /// 밑줄은 줄 단위다 — 밑줄 없는 큰 run(Menlo 40pt)이 같은 줄에 있으면 작은 run(Menlo
    /// 10pt)의 밑줄이 40pt 상자의 자리·두께로 내려간다 (한글 실측: Apple SD 40pt 무장식
    /// run 뒤 함초롬 10pt 밑줄 run이 Apple SD 40pt 자리). 같은 run의 취소선은 run 단위라
    /// 10pt 상자 그대로이므로, 한 줄 안의 취소선–밑줄 간격이 두 규칙을 한꺼번에 잡는다:
    /// 2.534 + 10.408 = 12.94pt (혼자면 2.534 + 2.602 = 5.14pt). 한글 문서에서는 run 크기
    /// 비례라 이런 일이 없다.
    func testMsWordUnderlineFollowsTheTallestRunOnTheLine() throws {
        let plainBig = run("Menlo", size: 40, color: Self.magenta)
        let small = run("Menlo", size: 10, color: Self.cyan, underline: true, strikethrough: true)
        var smallStrike = small
        smallStrike[HwpAttributedStringKey.strikethroughColor] = Self.magenta
        let text = NSMutableAttributedString(string: "AA ", attributes: plainBig)
        text.append(NSAttributedString(string: "bb", attributes: smallStrike))
        let raster = try render(text: text)
        let underline = try XCTUnwrap(Self.rowCenter(raster, where: Self.isCyan), "밑줄")
        let strike = try XCTUnwrap(Self.rowCenter(raster, where: Self.isMagenta), "취소선")
        let gap = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: menloBox(10), thicknessFontSize: 10
        ).center - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: menloBox(40)).center
        expect(underline - strike).to(beCloseTo(gap, within: 0.25))
        expect(gap).to(beCloseTo(12.942, within: 0.01))

        // 두께도 40pt 상자(2.33pt)다 — 빈칸 run으로 잰다.
        let blanks = NSMutableAttributedString(string: "    ", attributes: plainBig)
        blanks.append(NSAttributedString(
            string: "    ", attributes: run("Menlo", size: 10, color: Self.cyan, underline: true)
        ))
        let blankRaster = try render(text: blanks)
        let thickness = try XCTUnwrap(
            Self.lineThickness(blankRaster) { red, _, _ in red }, "밑줄 두께"
        )
        let bigCell = menloBox(40).cellHeight
        expect(thickness).to(beCloseTo(bigCell * 0.05, within: 0.06))
        expect(bigCell * 0.05).to(beCloseTo(2.328, within: 0.01))
    }

    /// 취소선은 run 단위다 — 같은 줄의 Menlo(CJK 갈래)·Helvetica(그 밖 갈래) 취소선 run이
    /// 각각 자기 상자의 `ascent` × 0.273에 놓인다 (한글 실측: Apple SD + 함초롬 두 취소선
    /// run이 각각 자기 자리).
    func testMsWordStrikethroughStaysPerRun() throws {
        let helvetica = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        try XCTSkipUnless(
            (CTFontCopyPostScriptName(helvetica) as String) == "Helvetica", "Helvetica 없음"
        )
        let size: CGFloat = 40
        let text = NSMutableAttributedString(
            string: "AA ",
            attributes: run("Menlo", size: size, color: Self.cyan, strikethrough: true)
        )
        text.append(NSAttributedString(
            string: "BB",
            attributes: run("Helvetica", size: size, color: Self.magenta, strikethrough: true)
        ))
        let raster = try render(text: text)
        let menlo = try XCTUnwrap(Self.rowCenter(raster, where: Self.isCyan), "Menlo 취소선")
        let helv = try XCTUnwrap(Self.rowCenter(raster, where: Self.isMagenta), "Helvetica 취소선")
        let helveticaBox = HwpMsWordLineBox.metrics(of: helvetica).scaled(by: size)
        let expected = HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: menloBox(size), thicknessFontSize: size
        ).center - HwpDecorationLineGeometry.msWordStrikethrough(
            runBox: helveticaBox, thicknessFontSize: size
        ).center
        // 위 방향 = 위에서부터 잰 행이 작아진다. Menlo 0.9282 vs Helvetica 0.8146 → 1.24pt.
        expect(helv - menlo).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(1.240, within: 0.02))
    }

    /// 글자 위 밑줄도 줄 상자의 `ascent` 위 0.021 cell — 같은 줄의 아래 밑줄과의 간격이
    /// cell + 0.042 cell = 1.042 × 23.28pt (Menlo 20pt) = 24.26pt.
    func testMsWordAboveUnderlineSitsOnTheLineBoxAscent() throws {
        let size: CGFloat = 20
        let text = NSMutableAttributedString(
            string: "AA ", attributes: run("Menlo", size: size, color: Self.cyan, underline: true)
        )
        text.append(NSAttributedString(
            string: "BB", attributes: run("Menlo", size: size, color: Self.magenta, above: true)
        ))
        let raster = try render(text: text)
        let below = try XCTUnwrap(Self.rowCenter(raster, where: Self.isCyan), "아래 밑줄")
        let above = try XCTUnwrap(Self.rowCenter(raster, where: Self.isMagenta), "위 밑줄")
        let box = menloBox(size)
        let expected = HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: box).center
            - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: box).center
        expect(below - above).to(beCloseTo(expected, within: 0.2))
        expect(expected).to(beCloseTo(box.cellHeight * 1.042, within: 0.001))
    }

    /// 문단 끝 글자의 상자(`msWordParagraphEndBox`)가 그 줄의 밑줄을 옮긴다 — Menlo 10pt
    /// 밑줄 run 하나에 Apple SD 산돌고딕 Neo 10pt 문단 끝 상자를 실으면 줄 상자의 높이는
    /// Apple SD(15.6pt), 베이스라인은 Menlo(11.03pt)가 되어 밑줄이 −3.02pt로 올라간다
    /// (한글 실측 `compat-decorations` 문단 "가나다밑줄": −0.3012em; Apple SD 혼자면 −0.3252).
    func testParagraphEndBoxJoinsTheLineBox() throws {
        let appleSD = CTFontCreateWithName("Apple SD Gothic Neo" as CFString, 10, nil)
        try XCTSkipUnless(
            (CTFontCopyPostScriptName(appleSD) as String) == "AppleSDGothicNeo-Regular",
            "Apple SD Gothic Neo 없음"
        )
        let appleBox = HwpMsWordLineBox.metrics(of: appleSD).scaled(by: 10)
        var attributes = run("Menlo", size: 10, color: Self.cyan, underline: true)
        let alone = try render(text: NSAttributedString(string: "AAAA", attributes: attributes))
        let aloneCenter = try XCTUnwrap(Self.rowCenter(alone, where: Self.isCyan), "혼자")
        attributes[HwpAttributedStringKey.msWordParagraphEndBox] = [
            NSNumber(value: Double(appleBox.lineHeight)),
            NSNumber(value: Double(appleBox.baseline)),
        ]
        let joined = try render(text: NSAttributedString(string: "AAAA", attributes: attributes))
        let joinedCenter = try XCTUnwrap(Self.rowCenter(joined, where: Self.isCyan), "합침")
        let line = try XCTUnwrap(HwpMsWordLineBox.union([menloBox(10), appleBox]))
        let expectedDrop = HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: menloBox(10))
            .center - HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: line).center
        // 합친 상자는 Menlo 혼자보다 깊다 (cell 12 > 11.64, descent 2.77 > 2.36).
        expect(joinedCenter - aloneCenter).to(beCloseTo(expectedDrop, within: 0.2))
        expect(expectedDrop).to(beCloseTo(0.42, within: 0.02))
    }

    /// 한글 2007 호환(raw 1)·훈민정음(raw 4) 문서의 run은 한글 문서 기하다 — MS 워드
    /// 값과 갈린다 (한글 실측: 훈민정음 = 한글 문서 그대로, 한글 2007은 별도 기하이지만
    /// 표본이 한 크기뿐이라 아직 한글 문서와 같이 다룬다).
    func testOtherCompatibleTargetsUseTheNativeGeometry() throws {
        for raw: UInt32 in [1, 4] {
            let attributes = run(
                "Menlo", size: 20, color: Self.cyan, underline: true, target: NSNumber(value: raw)
            )
            let raster = try render(
                text: NSAttributedString(string: "AAAA", attributes: attributes)
            )
            let center = try XCTUnwrap(Self.rowCenter(raster, where: Self.isCyan), "\(raw)")
            let native = try render(text: NSAttributedString(
                string: "AAAA",
                attributes: run("Menlo", size: 20, color: Self.cyan, underline: true, target: nil)
            ))
            let nativeCenter = try XCTUnwrap(Self.rowCenter(native, where: Self.isCyan), "native")
            expect(center).to(beCloseTo(nativeCenter, within: 0.1), description: "\(raw)")
        }
        // 대조: MS 워드는 갈린다 (−0.17 × 20 = −3.4 vs −5.204).
        let msWord = try render(text: NSAttributedString(
            string: "AAAA", attributes: run("Menlo", size: 20, color: Self.cyan, underline: true)
        ))
        let native = try render(text: NSAttributedString(
            string: "AAAA",
            attributes: run("Menlo", size: 20, color: Self.cyan, underline: true, target: nil)
        ))
        let msWordCenter = try XCTUnwrap(Self.rowCenter(msWord, where: Self.isCyan))
        let nativeCenter = try XCTUnwrap(Self.rowCenter(native, where: Self.isCyan))
        expect(msWordCenter - nativeCenter).to(beCloseTo(5.204 - 3.4, within: 0.2))
    }
}
