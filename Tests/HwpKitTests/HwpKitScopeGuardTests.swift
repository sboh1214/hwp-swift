import Foundation
import Nimble
import XCTest

/// HwpKit 공개 표면의 **스코프 가드** (#74).
///
/// `Sources/HwpKit/AGENTS.md`의 "v1 스코프 밖" 목록은 오래도록 문장으로만
/// 있었고 안티 패턴 항목은 "테스트로 grep 검증 있음"이라고 적혀 있었지만 실제
/// 스캐너는 없었다 — HwpKit 소스를 훑는 테스트가 하나도 없었고,
/// `SourceSafetyTests`는 `Sources/CoreHwp`만 본다. PDF 내보내기가 들어오면서
/// (이슈 #74) 이 경계가 처음으로 시험대에 오르므로 여기서 실물 가드를 세운다.
///
/// 경계는 **"바이트는 우리가, UI는 호스트가"**다. `HwpPDFExporter`는 PDF를
/// 만들어 돌려줄 뿐 저장 패널·공유 시트·인쇄 대화상자를 띄우지 않는다. 그
/// 반대편(파일 선택기·검색 UI·하이퍼링크 라우팅)도 마찬가지로 앱 책임이다.
final class HwpKitScopeGuardTests: XCTestCase {
    /// 호스트 앱이 소유해야 하는 UI 액션들. HwpKit이 이것을 직접 부르면
    /// 라이브러리가 호스트의 문서·공유·검색 정책을 가로채게 된다.
    private static let hostOwnedUIActions = [
        "ShareLink",
        "openURL",
        "fileExporter",
        "fileImporter",
        "searchable",
        "NSSavePanel",
        "NSOpenPanel",
        "NSPrintOperation",
        "printOperation",
        "UIPrintInteractionController",
        "UIActivityViewController",
        "UIDocumentPickerViewController",
    ]

    func testPublicSurfaceDelegatesHostOwnedUIToTheApp() throws {
        for sourceFile in try Self.hwpKitSourceFiles() {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for (number, line) in Self.executableLines(of: source) {
                for token in Self.hostOwnedUIActions {
                    expect(line).notTo(
                        contain(token),
                        description: "\(sourceFile.path):\(number)의 `\(token)`은 앱 책임이다"
                            + " (Sources/HwpKit/AGENTS.md \"v1 스코프 밖\")"
                    )
                }
            }
        }
    }

    /// AppKit/UIKit 직접 import 금지 — 플랫폼 뷰는 HwpKitNative의
    /// `Representable` wrapper를 통해서만 들어온다.
    func testPublicSurfaceDoesNotImportPlatformUIFrameworks() throws {
        for sourceFile in try Self.hwpKitSourceFiles() {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for (number, line) in Self.executableLines(of: source) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                for framework in ["AppKit", "UIKit", "PDFKit"] {
                    expect(trimmed == "import \(framework)").to(
                        beFalse(),
                        description: "\(sourceFile.path):\(number) — HwpKit은 \(framework)를"
                            + " 직접 import하지 않는다 (HwpKitNative 경유)"
                    )
                }
            }
        }
    }

    /// 가드가 실제로 무는지 — 토큰 목록이 비어 조용히 통과하는 상태를 막는다.
    func testGuardScansSourcesAndHasTokens() throws {
        let files = try Self.hwpKitSourceFiles()
        expect(files.count) >= 5
        expect(files.contains { $0.lastPathComponent == "HwpPDFExporter.swift" }) == true
        expect(Self.hostOwnedUIActions).toNot(beEmpty())
    }

    // MARK: - 스캔

    /// 주석만 있는 줄은 뺀다 — 이 파일이 막는 대상은 호출이지 설명이 아니고,
    /// `HwpPDFExporter`의 doc-comment는 호스트가 쓸 인쇄 API를 이름으로 안내한다.
    private static func executableLines(of source: String) -> [(Int, String)] {
        source.components(separatedBy: .newlines).enumerated().compactMap { offset, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                return nil
            }
            return (offset + 1, line)
        }
    }

    private static func hwpKitSourceFiles() throws -> [URL] {
        var root = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while root.lastPathComponent != "Tests", root.path != "/" {
            root.deleteLastPathComponent()
        }
        let sourceRoot = root
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("HwpKit")
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var urls = [URL]()
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true, url.pathExtension == "swift" {
                urls.append(url)
            }
        }
        return urls.sorted { $0.path < $1.path }
    }
}
