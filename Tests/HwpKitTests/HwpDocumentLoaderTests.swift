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

    /// 모든 오류 케이스에는 사용자에게 표시할 설명이 있으며, `NSError` 브리징 후에도
    /// `localizedDescription`이 기본 문구("error N")로 바뀌지 않는다 (R65, #117).
    /// 문구 자체는 바뀔 수 있으므로 고정하지 않는다. "비어 있지 않음,
    /// 케이스 간 구분, `reason` 보존"만 계약으로 삼는다.
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
        // 미지원 문서 종류별 설명을 포함해 모든 오류 설명이 서로 달라야 각각 구분해 안내할 수 있다
        expect(Set(errors.map(\.description)).count) == errors.count
        // 원인 문자열을 보존해야 호스트가 사용자에게 보여 줄 수 있다
        expect(HwpDocumentLoadError.presentationBuildFailed("stream limit exceeded").description)
            .to(contain("stream limit exceeded"))
    }

    /// 오류 매핑의 세 분기를 검증한다. 기존 `HwpDocumentLoadError`는 이중으로 감싸지 않고
    /// 그대로 전달하며, 미지원 문서는 종류를 보존하고, 그 밖의 오류는 원인 문자열로
    /// 감싼다 (#117).
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

    /// 암호로 보호된 문서, 배포용 문서, DRM 문서에 해당하는 픽스처를 읽을 때 오류가
    /// 단순 문자열로 변환되지 않고, 문서 종류를 보존한 `.unsupportedDocument`로 전달된다 (#117).
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

    /// `Data` 오버로드에서도 미지원 문서의 종류를 보존한다 (#117).
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

    /// `loadUpdates`의 프로그레시브 스트림도 미지원 문서의 종류를 보존한 오류를 던지고
    /// 종료된다 (#117).
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
