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

    /// localizedDescription이 NSError 브릿징 기본 문구("error N") 대신 감싼
    /// 파서/페이지네이터 원인을 노출한다 (R65).
    func testLoadErrorLocalizedDescriptionSurfacesWrappedReason() {
        let wrapped = HwpDocumentLoadError.presentationBuildFailed("stream limit exceeded")
        expect(wrapped.localizedDescription).to(contain("stream limit exceeded"))
        expect(HwpDocumentLoadError.cancelled.localizedDescription).to(contain("cancelled"))
        expect(HwpDocumentLoadError.invalidFileWrapper.localizedDescription)
            .to(contain("regular file"))
    }
}
