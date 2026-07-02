@testable import HwpKit
import Nimble
import XCTest

final class HwpDocumentLoaderTests: XCTestCase {
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
}
