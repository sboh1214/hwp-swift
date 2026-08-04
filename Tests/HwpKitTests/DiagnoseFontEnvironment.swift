import CoreGraphics
import CoreText
import Foundation
@testable import HwpKit
@testable import HwpKitCore
import XCTest

/// TEMPORARY — CI 폰트 환경 진단용. 원인 확정 후 삭제한다 (#95 리뷰).
///
/// `testDeterministic`은 7개 슬롯을 모두 Menlo로 고정하는데 Menlo엔 한글 글리프가
/// 없어 CoreText가 글자마다 호스트 폰트로 대체한다. 그 대체 결과가 러너마다 다르면
/// 커밋된 기준선(블록 좌표)이 갈린다 — p723 각주 블록이 정확히 그렇게 어긋났다.
/// 로컬과 CI의 수치를 같은 형식으로 찍어 어느 축이 다른지 확정한다.
final class DiagnoseFontEnvironment: XCTestCase {
    private func line(_ text: String, fontName: String) -> String {
        let font = CTFontCreateWithName(fontName as CFString, 10, nil)
        let attributed = NSAttributedString(
            string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let ctLine = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
        var fonts: [String] = []
        for run in CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as? [String: Any] ?? [:]
            guard let runFontAny = attributes[kCTFontAttributeName as String] else { continue }
            let runFont = unsafeBitCast(runFontAny as CFTypeRef, to: CTFont.self)
            fonts.append(CTFontCopyPostScriptName(runFont) as String)
        }
        return String(
            format: "실제=%@ h=%.3f w=%.3f (a=%.3f d=%.3f l=%.3f)",
            fonts.joined(separator: "+"), ascent + descent + leading, width,
            ascent, descent, leading
        )
    }

    func testReportFontEnvironment() async throws {
        print("DIAG os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("DIAG 한글/Menlo      \(line("각주 참조", fontName: "Menlo"))")
        print("DIAG 라틴/Menlo      \(line("27) ", fontName: "Menlo"))")
        print("DIAG 혼합/Menlo      \(line("27) 장석조(", fontName: "Menlo"))")
        print("DIAG 한글/AppleSD    \(line("각주 참조", fontName: "Apple SD Gothic Neo"))")
        print("DIAG 희귀한자/Menlo  \(line("頉", fontName: "Menlo"))")

        guard let fixture = try FixtureRoot.loadAllFixtures(from: #file).first(
            where: { $0.id == "legacy-common-control-property" }
        ) else { return XCTFail("fixture 없음") }
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixture.documentURL)
        guard document.pages.indices.contains(723) else { return XCTFail("p723 없음") }
        for (index, block) in document.pages[723].blocks.enumerated()
            where block.kind == .footnote
        {
            let text = (block.attributedString?.string ?? "").prefix(10)
                .replacingOccurrences(of: "\n", with: " ")
            print(String(
                format: "DIAG p723 블록#%d y=%.1f h=%.1f '%@'",
                index, block.frame.minY, block.frame.height, String(text)
            ))
        }
    }
}
