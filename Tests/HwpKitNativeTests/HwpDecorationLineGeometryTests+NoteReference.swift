import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 각주·미주 참조 번호의 취소선 (#256) — 번호 글리프는 0.75배로 줄고 설정 크기의 0.21배 올라가지만
/// (#204), 번호의 취소선(글자 가운데 밑줄 포함)은 **번호가 놓인 글자 모양의 자리·두께 그대로**다.
/// 위 첨자 글자 모양 안의 번호는 그 첨자의 선 자리를 따른다. 한편 번호는 앞뒤 글자와 **따로 된 글자
/// 모양 run**이라, 선 모양 무늬는 번호 시작·번호 뒤 글자 시작에서 새로 시작하고 MS 워드 호환 문서의
/// 취소선 글꼴도 번호는 자기 글꼴, 번호 뒤 글자는 자기 첫 글리프 글꼴이다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-06, 합성 HWPX — 한글 문서·한글 2007
/// 호환·MS 워드 호환 × 함초롬바탕·함초롬돋움 10·20·40·80pt 본문 + 미주·글자 가운데 밑줄·상대 크기
/// 50%·위 첨자 글자 모양 안의 각주·긴 점선 취소선·슬롯 글꼴 섞임, 각주 내용의 위 첨자 번호):
///
/// | 표본 (본문 기준선 위, pt) | 본문 선 | 번호 선 | 종전 우리 번호 선 |
/// |---|---:|---:|---:|
/// | 한글 문서 함초롬바탕 20pt | 6.96 | 6.96 | 9.45 |
/// | 한글 문서 함초롬바탕 80pt | 27.96 | 27.96 | 37.80 |
/// | MS 워드 호환 함초롬바탕 20pt | 5.88 | 5.88 | 8.27 |
/// | 한글 2007 호환 함초롬바탕 40pt | 13.92 | 13.92 | 18.90 |
/// | 한글 문서 40pt 위 첨자 run 안 | 26.52 (첨자 선) | 26.52 | 32.72 |
///
/// 선 두께는 모든 표본에서 본문과 같다 (한글 문서·MS 워드 호환 20pt 0.84pt, 한글 2007 호환 0.36pt).
/// 쪽 좌표의 실물 핀은 `note-reference-strikethrough` 픽스처 쌍
/// (`FixtureDecorationLineRenderTests+NoteReference`)이다.
///
/// `extension`에 두는 이유는 `HwpDecorationLineGeometryTests` 본문이 `type_body_length`
/// 경고선에 닿아 있어서다. 래스터·측정 헬퍼는 `+Support`.
extension HwpDecorationLineGeometryTests {
    private static let noteBodySize: CGFloat = 20
    /// `HwpTextRunBuilder.noteReferenceScale` — 참조 번호 글꼴 축소 (#204)
    private static let noteScale: CGFloat = 0.75
    /// `HwpTextRunBuilder.noteReferenceBaselineRatio` — 참조 번호 올림 (설정 크기 대비)
    private static let noteRaise: CGFloat = 0.21
    /// `HwpTextRunBuilder.superscriptScale`·`superscriptBaselineRatio` — 글자 모양 위 첨자
    private static let charScriptScale: CGFloat = 0.64
    private static let charScriptRaise: CGFloat = 0.44

    /// 조판이 싣는 run 속성을 흉내 낸다 — 기본 `size`, 글자 모양 id 7. `superscript`면 글자 모양 위
    /// 첨자 run(0.64배 글꼴, 첨자 몫 키 두 개), `note`가 있으면 그 순번의 참조 번호 run(글꼴 0.75배 더,
    /// 올림은 합산 키에만, `noteReferenceScale`). `marker`는 참조 번호가 아닌 컨트롤 치환 run(쪽 번호
    /// 등 — 순번만 있고 번호 키는 없다). `fontName`은 run 글꼴.
    private func noteRun(
        size: CGFloat = noteBodySize, color: CGColor, target: HwpCompatibleDocumentTarget?,
        superscript: Bool = false, note: Int? = nil, marker: Int? = nil,
        fontName: String = "Menlo", shape: HwpBorderType? = nil
    ) -> [NSAttributedString.Key: Any] {
        var fontSize = size
        var glyphShift: CGFloat = 0
        var attributes: [NSAttributedString.Key: Any] = [
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(size)),
            HwpAttributedStringKey.charShapeId: NSNumber(value: 7),
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: color,
        ]
        if let target {
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                value: target.rawValue
            )
        }
        if let shape {
            attributes[HwpAttributedStringKey.strikethroughShape] = NSNumber(
                value: shape.rawValue
            )
        }
        if superscript {
            fontSize *= Self.charScriptScale
            glyphShift += Self.charScriptRaise * size
            attributes[HwpAttributedStringKey.scriptBaselineOffset] = NSNumber(
                value: Double(Self.charScriptRaise * size)
            )
        }
        if let note {
            fontSize *= Self.noteScale
            glyphShift += Self.noteRaise * size
            attributes[HwpAttributedStringKey.noteReferenceScale] = NSNumber(
                value: Double(Self.noteScale)
            )
            attributes[HwpAttributedStringKey.controlIndex] = NSNumber(value: note)
        }
        if let marker {
            attributes[HwpAttributedStringKey.controlIndex] = NSNumber(value: marker)
        }
        if glyphShift != 0 {
            attributes[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(
                value: Double(glyphShift)
            )
        }
        attributes[kCTFontAttributeName as NSAttributedString.Key] = CTFontCreateWithName(
            fontName as CFString, fontSize, nil
        )
        return attributes
    }

    /// 렌더러가 그 run의 취소선에 쓰는 기하 — `drawStrikethroughIfNeeded`와 같은 경로
    /// (`strikethroughRunFontSize`로 무른 크기 → `strikethroughLine`).
    private func strikethroughGeometry(
        _ attributes: [NSAttributedString.Key: Any], msWordFont: CTFont?
    ) -> HwpDecorationLineGeometry.Line {
        let layer = HwpPageLayer()
        return layer.strikethroughLine(
            attributes, msWordFont: msWordFont,
            fontSize: layer.strikethroughRunFontSize(attributes)
        )
    }

    /// 세 문서 갈래 모두 번호의 취소선 = 같은 글자 모양 본문의 취소선 (자리·두께). 종전에는 번호의
    /// 0.75배 글꼴을 첨자로 읽어 한글 문서 20pt에서 0.35 × 15 = 5.25pt(올림 4.2를 더하면 본문 기준선 위
    /// 9.45pt)·MS 워드 호환 문서에서 보통 높이의 0.696배에 그렸다.
    func testNoteReferenceStrikethroughGeometryMatchesTheBodyInEveryFormat() {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let size = Self.noteBodySize
        for target in [nil, HwpCompatibleDocumentTarget.hwp200X, .msWord] {
            let label = String(describing: target)
            let body = noteRun(color: cyan, target: target)
            let number = noteRun(color: cyan, target: target, note: 0)
            let msWordFont: CTFont? = target == .msWord
                ? CTFontCreateWithName("Menlo" as CFString, size, nil) : nil
            let bodyLine = strikethroughGeometry(body, msWordFont: msWordFont)
            let numberLine = strikethroughGeometry(number, msWordFont: msWordFont)
            expect(numberLine.center)
                .to(beCloseTo(bodyLine.center, within: 0.000_1), description: label)
            expect(numberLine.thickness)
                .to(beCloseTo(bodyLine.thickness, within: 0.000_1), description: label)
            expect(HwpPageLayer().strikethroughRunFontSize(number))
                .to(beCloseTo(size, within: 0.000_1), description: label)
        }
        // 한글 문서 20pt: 0.35 × 20 = 7.0pt (한글 6.96 — 장치 0.12pt 양자화)
        let native = strikethroughGeometry(
            noteRun(color: cyan, target: nil, note: 0), msWordFont: nil
        )
        expect(native.center).to(beCloseTo(7.0, within: 0.000_1))
    }

    /// 위 첨자 글자 모양 안의 번호는 그 첨자의 선 자리 — 번호 축소만 무르고 첨자 축소(0.64)는 남아 첨자로
    /// 판정된다. 한글 40pt(함초롬바탕): 첨자 선과 번호 선 모두 +26.52pt, MS 워드 호환은 둘 다 +25.68pt
    /// (장치 0.12pt 양자화 — 우리 모형은 0.44 × 40 + 0.35 × 40 × 89/140 = 26.50, MS 워드는 #257 모형으로
    /// 17.6 + 0.696 × 11.64 = 25.70; 이 테스트의 Menlo는 0.696 × 10.146이다).
    /// 첨자 몫 키는 두 run이 같고(0.44 × 40), 선 자리는 그 위에 더해진다.
    func testNoteReferenceInsideSuperscriptFollowsTheScriptStrikethrough() {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let size: CGFloat = 40
        for target in [nil, HwpCompatibleDocumentTarget.hwp200X, .msWord] {
            let label = String(describing: target)
            let scripted = noteRun(size: size, color: cyan, target: target, superscript: true)
            let number = noteRun(
                size: size, color: cyan, target: target, superscript: true, note: 0
            )
            let msWordFont: CTFont? = target == .msWord
                ? CTFontCreateWithName("Menlo" as CFString, size, nil) : nil
            let scriptLine = strikethroughGeometry(scripted, msWordFont: msWordFont)
            let numberLine = strikethroughGeometry(number, msWordFont: msWordFont)
            expect(numberLine.center)
                .to(beCloseTo(scriptLine.center, within: 0.000_1), description: label)
            expect(numberLine.thickness)
                .to(beCloseTo(scriptLine.thickness, within: 0.000_1), description: label)
        }
        let native = strikethroughGeometry(
            noteRun(size: size, color: cyan, target: nil, superscript: true, note: 0),
            msWordFont: nil
        )
        expect(native.center).to(beCloseTo(
            0.35 * size * HwpRenderTuning.Text.scriptStrikethroughScale, within: 0.000_1
        ))
    }

    /// 픽셀로 — 본문(청록) · 번호(자홍) · 본문(청록)을 한 줄에 그리면 세 문서 갈래 모두 번호 선이 본문
    /// 선과 같은 행·같은 두께다. 번호 글리프는 4.2pt 올라가 있으므로 선이 글리프를 따라가는 회귀
    /// (종전)는 한글 문서 20pt에서 2.45pt, MS 워드 호환 문서에서 4.2 − 0.304 × 5.07 = 2.66pt 위로
    /// 갈린다.
    func testNoteReferenceStrikethroughSitsOnTheBodyRowInARaster() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        for target in [nil, HwpCompatibleDocumentTarget.hwp200X, .msWord] {
            let label = String(describing: target)
            let text = NSMutableAttributedString(
                string: "xx", attributes: noteRun(color: cyan, target: target)
            )
            text.append(NSAttributedString(
                string: "12)", attributes: noteRun(color: magenta, target: target, note: 0)
            ))
            text.append(NSAttributedString(
                string: "xx", attributes: noteRun(color: cyan, target: target)
            ))
            let raster = try render(text: text)
            let body = try XCTUnwrap(
                Self.rowCenter(raster) { $0 < 100 && $1 > 150 && $2 > 150 }, "\(label) 본문 선"
            )
            let number = try XCTUnwrap(
                Self.rowCenter(raster) { $0 > 150 && $1 < 100 && $2 > 150 }, "\(label) 번호 선"
            )
            expect(number).to(beCloseTo(body, within: 0.1), description: label)

            // 두께는 빈칸 run으로 잰다 — 글리프 잉크가 없어야 열의 커버리지가 선뿐이다
            // (`thicknessProbe`와 같은 방식: 청록은 R, 자홍은 G 채널).
            let blank = NSMutableAttributedString(
                string: "    ", attributes: noteRun(color: cyan, target: target)
            )
            blank.append(NSAttributedString(
                string: "    ", attributes: noteRun(color: magenta, target: target, note: 0)
            ))
            let blankRaster = try render(text: blank)
            let bodyThickness = try XCTUnwrap(
                Self.lineThickness(blankRaster) { red, _, _ in red }, "\(label) 본문 두께"
            )
            let numberThickness = try XCTUnwrap(
                Self.lineThickness(blankRaster) { _, green, _ in green }, "\(label) 번호 두께"
            )
            expect(numberThickness).to(beCloseTo(bodyThickness, within: 0.05), description: label)
        }
    }

    /// 무늬 묶음은 번호에서 끊긴다 — 번호는 앞뒤 본문과 떨어지고, 한 번호가 슬롯으로 갈린 run끼리는
    /// 붙고, 붙은 두 번호는 순번이 달라 떨어진다. 번호 뒤 본문은 번호 앞 본문과 같은 묶음 열쇠다 —
    /// 사이에 번호가 끼면 `lineShapeSpans`가 번호에서 새 묶음을 열었으므로 거기서 다시 시작한다.
    func testNoteReferenceSplitsTheLineShapeGroup() {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        for target in [nil, HwpCompatibleDocumentTarget.hwp200X, .msWord] {
            let label = String(describing: target)
            let body = noteRun(color: cyan, target: target, shape: .longDash)
            let number = noteRun(color: cyan, target: target, note: 3, shape: .longDash)
            let numberSlot = noteRun(
                color: cyan, target: target, note: 3, fontName: "Helvetica", shape: .longDash
            )
            let nextNumber = noteRun(color: cyan, target: target, note: 4, shape: .longDash)
            expect(HwpPageLayer.sameLineShapeGroup(body, body)).to(beTrue(), description: label)
            expect(HwpPageLayer.sameLineShapeGroup(body, number)).to(beFalse(), description: label)
            expect(HwpPageLayer.sameLineShapeGroup(number, body)).to(beFalse(), description: label)
            expect(HwpPageLayer.sameLineShapeGroup(number, numberSlot))
                .to(beTrue(), description: label)
            expect(HwpPageLayer.sameLineShapeGroup(number, nextNumber))
                .to(beFalse(), description: label)
            // 음성 대조군 — 순번만 있고 번호 키가 없는 컨트롤 치환 run(쪽 번호 등)은 앞뒤 글자와
            // 같은 묶음이다. 신원을 순번만으로 정하면 그런 run에서도 무늬가 다시 시작한다.
            let marker = noteRun(color: cyan, target: target, marker: 5, shape: .longDash)
            expect(HwpPageLayer.sameLineShapeGroup(body, marker)).to(beTrue(), description: label)
            expect(HwpPageLayer.sameLineShapeGroup(marker, body)).to(beTrue(), description: label)
        }
    }

    /// CoreText run 단위로 — 긴 점선 본문 · 번호 · 본문 줄의 무늬 span은 세 묶음(본문 앞, 번호, 본문
    /// 뒤)마다 첫 run이 받는다. 한글도 번호 시작(본문 앞 마지막 대시가 잘린 자리)과 번호 뒤 글자
    /// 시작에서 대시를 새로 시작한다 (40pt: 대시 22.92·틈 6.96, 번호 시작 221.76에 온 대시). 종전에는
    /// 번호가 첨자 몫 키로 갈려 같은 결과였지만, 그 키를 번호에 싣지 않게 된 뒤로는 이 신원만이 가른다.
    func testNoteReferenceRestartsTheLineShapeSpan() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let text = NSMutableAttributedString(
            string: "xxxx", attributes: noteRun(color: cyan, target: nil, shape: .longDash)
        )
        text.append(NSAttributedString(
            string: "1)", attributes: noteRun(color: cyan, target: nil, note: 1, shape: .longDash)
        ))
        text.append(NSAttributedString(
            string: "xxxx", attributes: noteRun(color: cyan, target: nil, shape: .longDash)
        ))
        let line = CTLineCreateWithAttributedString(text)
        let runs = try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun])
        expect(runs.count) == 3
        let spans = HwpPageLayer().lineShapeSpans(of: runs, lineOrigin: .zero)
        expect(spans.map { $0 != nil }) == [true, true, true]
    }

    /// MS 워드 호환 문서의 취소선 글꼴 묶음도 번호에서 끊긴다 — 한글 실측(한글 슬롯 함초롬바탕·라틴
    /// 슬롯 Apple SD 40pt): `가나L` + 번호 + `AB`에서 `가나L`은 함초롬 자리, 번호와 `AB`는 각각 자기
    /// 첫 글리프 Apple SD 자리였고, `ABM` + 번호 + `가나`에서 `가나`는 함초롬 자리였다(`가나K` + 번호
    /// + `다라`의 `다라`도 번호 글꼴이 아니라 함초롬 자리). 여기서는 한글 슬롯 Apple SD 산돌고딕 Neo·
    /// 라틴 슬롯 Menlo로 같은 구성을 만든다 — 종전에는 같은 글자 모양 id라 줄 전체가 첫 글리프 글꼴
    /// 하나였다.
    func testNoteReferenceStartsItsOwnMsWordStrikethroughFont() throws {
        let cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
        let hangul = "AppleSDGothicNeo-Regular"
        // run 하나 — 문자열·글꼴 PostScript 이름·참조 번호 순번(본문이면 nil)·참조 번호가 아닌
        // 컨트롤 치환 순번(`marker`)
        struct Part {
            let text: String
            let font: String
            let note: Int?
            let marker: Int?

            init(_ text: String, _ font: String, _ note: Int? = nil, marker: Int? = nil) {
                self.text = text
                self.font = font
                self.note = note
                self.marker = marker
            }
        }
        func fonts(_ parts: [Part]) throws -> [String] {
            let text = NSMutableAttributedString()
            for part in parts {
                text.append(NSAttributedString(
                    string: part.text,
                    attributes: noteRun(
                        size: 40, color: cyan, target: .msWord, note: part.note,
                        marker: part.marker, fontName: part.font
                    )
                ))
            }
            let line = CTLineCreateWithAttributedString(text)
            let runs = try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun])
            expect(runs.count) == parts.count
            return HwpPageLayer().msWordStrikethroughFonts(of: runs).map { font in
                font.map { CTFontCopyPostScriptName($0) as String } ?? "-"
            }
        }
        expect(try fonts([
            Part("가나", hangul), Part("K", "Menlo"), Part("15)", "Menlo", 1), Part("AB", "Menlo"),
        ])) == [hangul, hangul, "Menlo-Regular", "Menlo-Regular"]
        expect(try fonts([Part("AB", "Menlo"), Part("16)", "Menlo", 2), Part("가나", hangul)]))
            == ["Menlo-Regular", "Menlo-Regular", hangul]
        // 번호가 없으면 종전대로 한 글자 모양 run — 첫 글리프 글꼴 하나다.
        expect(try fonts([Part("가나", hangul), Part("AB", "Menlo")])) == [hangul, hangul]
        // 참조 번호가 아닌 컨트롤 치환 run(순번만 있다)도 묶음을 끊지 않는다.
        expect(try fonts([Part("가나", hangul), Part("7", "Menlo", marker: 3), Part("AB", "Menlo")]))
            == [hangul, hangul, hangul]
    }
}
