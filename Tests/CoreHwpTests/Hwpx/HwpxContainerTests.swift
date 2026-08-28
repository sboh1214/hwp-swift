@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpxContainerTests: XCTestCase {
    private let limits = HwpReadLimits.default

    private func makeArchive(
        mimetype: String? = "application/hwp+zip",
        extraEntries: [ZipBuilder.Entry] = []
    ) -> Data {
        var builder = ZipBuilder()
        if let mimetype {
            builder.entries.append(.init(
                name: "mimetype", content: Data(mimetype.utf8), method: 0
            ))
        }
        builder.entries.append(contentsOf: extraEntries)
        return builder.build()
    }

    func testOpensValidContainerAndReadsEntries() throws {
        let header = Data("<hh:head/>".utf8)
        var container = try HwpxContainer(
            data: makeArchive(extraEntries: [
                .init(name: "Contents/header.xml", content: header, method: 8),
            ]),
            limits: limits
        )

        expect(container.hasEntry("Contents/header.xml")) == true
        expect(try container.requiredEntry("Contents/header.xml")) == header
        expect(try container.optionalEntry("settings.xml")).to(beNil())
    }

    func testAcceptsMimetypeWithTrailingNewline() throws {
        _ = try HwpxContainer(
            data: makeArchive(mimetype: "application/hwp+zip\n"), limits: limits
        )
    }

    func testMissingMimetypeThrowsInvalidArchive() {
        expect {
            _ = try HwpxContainer(data: self.makeArchive(mimetype: nil), limits: self.limits)
        }.to(throwError { error in
            guard case let HwpError.invalidArchive(reason) = error else {
                return fail("Expected invalidArchive, got \(error)")
            }
            expect(reason).to(contain("missing 'mimetype'"))
        })
    }

    func testForeignZipMimetypeThrowsInvalidArchive() {
        // .docx 계열 ZIP이 하류 XML 오류로 표류하지 않고 컨테이너 게이트에서
        // 명확히 거부되는지 — HWPX 판정의 핵심 게이트다.
        expect {
            _ = try HwpxContainer(
                data: self.makeArchive(
                    mimetype: "application/vnd.openxmlformats-officedocument" +
                        ".wordprocessingml.document"
                ),
                limits: self.limits
            )
        }.to(throwError { error in
            guard case let HwpError.invalidArchive(reason) = error else {
                return fail("Expected invalidArchive, got \(error)")
            }
            expect(reason).to(contain("unexpected mimetype"))
        })
    }

    func testEncryptionEntryThrowsUnsupportedFeature() {
        expect {
            _ = try HwpxContainer(
                data: self.makeArchive(extraEntries: [
                    .init(
                        name: "META-INF/encryption.xml",
                        content: Data("<encryption/>".utf8),
                        method: 0
                    ),
                ]),
                limits: self.limits
            )
        }.to(throwError { error in
            guard case HwpError.unsupportedFeature(.encryptedDocument) = error else {
                return fail("Expected unsupportedFeature(.encryptedDocument), got \(error)")
            }
        })
    }

    func testSectionEntryNamesSortNumerically() throws {
        let sectionNames = (0 ... 10).map { "Contents/section\($0).xml" }
        let container = try HwpxContainer(
            data: makeArchive(extraEntries: sectionNames.shuffled().map {
                .init(name: $0, content: Data("<hs:sec/>".utf8), method: 0)
            }),
            limits: limits
        )

        // 사전순이라면 section10이 section2 앞에 온다 — 숫자 정렬 확인.
        expect(container.sectionEntryNames) == sectionNames
    }

    func testSectionIndexRejectsNonSectionNames() {
        expect(HwpxContainer.sectionIndex(of: "Contents/section0.xml")) == 0
        expect(HwpxContainer.sectionIndex(of: "Contents/section12.xml")) == 12
        expect(HwpxContainer.sectionIndex(of: "Contents/section.xml")).to(beNil())
        expect(HwpxContainer.sectionIndex(of: "Contents/sectionA.xml")).to(beNil())
        expect(HwpxContainer.sectionIndex(of: "Contents/header.xml")).to(beNil())
        expect(HwpxContainer.sectionIndex(of: "section0.xml")).to(beNil())
    }
}
