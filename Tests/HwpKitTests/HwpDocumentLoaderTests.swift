@testable import CoreHwp
@testable import HwpKit
@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

final class HwpDocumentLoaderTests: XCTestCase {
    func testActorEmitsAtLeastOnePageFromBlankFile() async throws {
        let actor = HwpDocumentActor()
        let file = CoreHwp.HwpFile()
        let doc = try await actor.loadDocument(from: file)
        expect(doc.pages.count) >= 1
    }

    func testMalformedDataThrowsPresentationBuildFailed() async {
        let loader = HwpDocumentLoader()
        let badData = Data([0x00, 0x01, 0x02, 0x03])
        await expect { try await loader.load(from: badData) }
            .to(throwError(errorType: HwpDocumentLoadError.self) { error in
                if case .presentationBuildFailed = error { } else {
                    fail("Expected .presentationBuildFailed, got \(error)")
                }
            })
    }

    func testInvalidFileWrapperThrowsInvalidFileWrapper() async {
        let loader = HwpDocumentLoader()
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        await expect { try await loader.load(from: wrapper) }
            .to(throwError(errorType: HwpDocumentLoadError.self) { error in
                if case .invalidFileWrapper = error { } else {
                    fail("Expected .invalidFileWrapper, got \(error)")
                }
            })
    }

    /// 전 케이스가 사용자 표시용 서술을 갖고, localizedDescription이 NSError
    /// 브릿징 기본 문구("error N")로 퇴화하지 않는다 (R65, #117).
    /// 특정 문구를 못 박지 않는다 — 문구는 바뀔 수 있고 계약은
    /// "비지 않음 + 케이스 간 구별 + reason 유실 없음"이다.
    func testErrorDescriptionsCoverEveryCase() {
        let errors: [HwpDocumentLoadError] = [
            .cancelled,
            .invalidFileWrapper,
            .presentationBuildFailed("stream limit exceeded"),
            .unsupportedDocument(.encryptedDocument),
            .unsupportedDocument(.deploymentDocument),
            .unsupportedDocument(.drmDocument),
        ]

        for error in errors {
            expect(error.description).toNot(beEmpty())
            expect(error.errorDescription) == error.description
            expect(error.localizedDescription) == error.description
        }
        // 케이스(미지원 종류 포함)마다 서술이 서로 달라야 안내가 갈린다
        expect(Set(errors.map(\.description)).count) == errors.count
        // 사유는 유실되지 않는다 — 호스트가 원인을 보여 줄 수 있어야 한다
        expect(HwpDocumentLoadError.presentationBuildFailed("stream limit exceeded").description)
            .to(contain("stream limit exceeded"))
    }

    /// 매핑 관문 세 갈래 — passthrough(이중 래핑 금지)·타입 보존·문자열 래핑 (#117).
    func testMapLoadFailureBranches() {
        struct DummyError: Error {}

        let passthrough = HwpDocumentLoader.mapLoadFailure(HwpDocumentLoadError.invalidFileWrapper)
        guard case .invalidFileWrapper = passthrough else {
            return fail("Expected passthrough of .invalidFileWrapper, got \(passthrough)")
        }
        let typed = HwpDocumentLoader.mapLoadFailure(HwpError.unsupportedFeature(.drmDocument))
        guard case .unsupportedDocument(.drmDocument) = typed else {
            return fail("Expected .unsupportedDocument(.drmDocument), got \(typed)")
        }
        let wrapped = HwpDocumentLoader.mapLoadFailure(DummyError())
        guard case let .presentationBuildFailed(reason) = wrapped else {
            return fail("Expected .presentationBuildFailed, got \(wrapped)")
        }
        expect(reason) == DummyError().localizedDescription
    }

    /// 암호·배포용·DRM 픽스처가 문자열로 뭉개지지 않고 종류가 보존된
    /// `.unsupportedDocument`로 올라온다 (#117).
    func testUnsupportedFixturesThrowTypedUnsupportedDocument() async {
        let cases: [(id: String, kind: HwpUnsupportedDocumentKind)] = [
            ("문서암호설정-보안수준높음", .encryptedDocument),
            ("문서암호설정-보안수준보통", .encryptedDocument),
            ("배포용문서", .deploymentDocument),
            ("drm-unsupported-derived", .drmDocument),
        ]
        let loader = HwpDocumentLoader()
        for (id, kind) in cases {
            let url = FixtureRoot.url(from: #filePath)
                .appendingPathComponent(id)
                .appendingPathComponent("document.hwp")
            await expect { try await loader.load(from: url) }
                .to(throwError(errorType: HwpDocumentLoadError.self) { error in
                    guard case .unsupportedDocument(kind) = error else {
                        return fail("Expected .unsupportedDocument(\(kind)), got \(error)")
                    }
                })
        }
    }

    /// Data 오버로드도 같은 타입 보존 매핑을 지난다 (#117).
    func testUnsupportedDataThrowsTypedUnsupportedDocument() async throws {
        let url = FixtureRoot.url(from: #filePath)
            .appendingPathComponent("문서암호설정-보안수준높음")
            .appendingPathComponent("document.hwp")
        let data = try Data(contentsOf: url)
        let loader = HwpDocumentLoader()
        await expect { try await loader.load(from: data) }
            .to(throwError(errorType: HwpDocumentLoadError.self) { error in
                guard case .unsupportedDocument(.encryptedDocument) = error else {
                    return fail("Expected .unsupportedDocument(.encryptedDocument), got \(error)")
                }
            })
    }

    /// 프로그레시브 스트림도 미지원 문서를 타입 보존해 종료한다 (#117).
    func testLoadUpdatesSurfacesTypedUnsupportedDocument() async {
        let url = FixtureRoot.url(from: #filePath)
            .appendingPathComponent("배포용문서")
            .appendingPathComponent("document.hwp")
        let loader = HwpDocumentLoader()
        let stream = await loader.loadUpdates(from: url)
        await expect {
            for try await _ in stream {}
        }
        .to(throwError(errorType: HwpDocumentLoadError.self) { error in
            guard case .unsupportedDocument(.deploymentDocument) = error else {
                return fail("Expected .unsupportedDocument(.deploymentDocument), got \(error)")
            }
        })
    }
}
