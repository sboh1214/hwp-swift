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
/// 경계는 **"바이트와 컴포넌트는 우리가, 호스트 chrome과 정책은 호스트가"**다.
/// `HwpPDFExporter`는 PDF를 만들어 돌려줄 뿐 저장 패널·공유 시트·인쇄
/// 대화상자를 띄우지 않는다.
///
/// **UI 자체가 금지된 것은 아니다** — `HwpPageNavigator`/`HwpZoomControls`/
/// `HwpSearchBar`(#75)는 호스트가 놓은 자리만 차지하는 순수 서브트리라
/// navigation 컨테이너를 요구하지도, 창 툴바·내비게이션 바 슬롯을 점유하지도,
/// 환경을 오염시키지도, 전역 단축키를 소유하지도 않는다. 아래 토큰이 막는
/// 것은 그 반대편, 즉 **호스트 chrome에 자기를 설치하거나 시스템 모달을
/// 개시하는** API다. 파일 선택기·하이퍼링크 라우팅·저장 패널은 여전히 앱
/// 책임이다.
final class HwpKitScopeGuardTests: XCTestCase {
    /// 호스트 앱이 소유해야 하는 UI 액션들. HwpKit이 이것을 직접 부르면
    /// 라이브러리가 호스트의 문서·공유·chrome 정책을 가로채게 된다.
    ///
    /// `searchable`이 목록에 있는 이유는 검색 기능 때문이 **아니다** — SwiftUI의
    /// `.searchable`은 자기 자리에 필드를 그리지 않고 가장 가까운 navigation
    /// 컨테이너의 chrome(창 툴바 / 내비게이션 바)에 검색 필드를 **설치**하고
    /// `\.isSearching`을 환경에 심기 때문이다. 검색 UI 자체는 `HwpSearchBar`가
    /// 독립 `View`로 제공한다(#75). 이 토큰은 그 설계를 지키는 가드다.
    ///
    /// 가드가 부분 문자열 매칭이므로 HwpKit 안에서는 소문자 `searchable` 어근을
    /// 쓴 식별자(`isSearchable` 등)도 쓸 수 없다 — 명명은 `HwpSearch*`로 고정.
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
        // 이 두 단언은 서로를 지탱한다 — '검색 UI가 HwpKit에 **실재하는데**
        // `searchable` 토큰도 **살아 있다**'는 상태 자체가 위 doc-comment의
        // 경계 판정에 대한 증거다. 나중에 누가 `HwpSearchBar`를 `.searchable`로
        // 갈아엎으면 둘 중 하나가 반드시 깨진다.
        expect(files.contains { $0.lastPathComponent == "HwpSearchBar.swift" }) == true
        expect(Self.hostOwnedUIActions).to(contain("searchable"))
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
