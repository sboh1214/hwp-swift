@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpLoadOptions.recoverPartialContent` (#65) — 손상 문단·구역의
/// placeholder 전환 매트릭스.
///
/// default 모드는 기존 fail-fast typed error를 그대로 던지고, recover
/// 모드는 실패 지점만 placeholder(`parseFailure` + 원본 레코드 보존)로
/// 바꿔 나머지 본문을 보존해야 한다. 구역 스트림 구조 자체의 손상은
/// `HwpSection.load`에서 양 모드 모두 throw하고, 구역 단위 복구는
/// `HwpFile` 조립이 맡는다.
final class ParagraphRecoveryPlaceholderTests: XCTestCase {
    private let version = HwpVersion(5, 0, 1, 1)
    private let recoverOptions = HwpLoadOptions(recoverPartialContent: true)

    // MARK: - 문단 카운트 4종 + 필수 레코드 누락 placeholder 전환 매트릭스

    func testCharShapeCountMismatchBecomesPlaceholderOnlyInRecoverMode() throws {
        try assertMiddleParagraphRecovery(
            corrupt: recoveryParagraphData(
                headerPayload: recoveryParaHeaderPayload(charShapeInfoCount: 2),
                charShapePayload: recoveryCharShapePairPayload()
            ),
            expectedFailure: "paragraph char shape count mismatch"
        )
    }

    func testParaTextCountMismatchBecomesPlaceholderOnlyInRecoverMode() throws {
        try assertMiddleParagraphRecovery(
            corrupt: recoveryParagraphData(
                headerPayload: recoveryParaHeaderPayload(charCount: 2),
                paraTextPayload: recoveryLittleEndianData(WCHAR(0xAC00))
            ),
            expectedFailure: "paragraph text count mismatch"
        )
    }

    func testLineSegCountMismatchBecomesPlaceholderOnlyInRecoverMode() throws {
        try assertMiddleParagraphRecovery(
            corrupt: recoveryParagraphData(
                headerPayload: recoveryParaHeaderPayload(alignInfoCount: 2),
                lineSegPayload: recoveryLineSegEntryPayload()
            ),
            expectedFailure: "paragraph line segment count mismatch"
        )
    }

    func testRangeTagCountMismatchBecomesPlaceholderOnlyInRecoverMode() throws {
        try assertMiddleParagraphRecovery(
            corrupt: recoveryParagraphData(
                headerPayload: recoveryParaHeaderPayload(rangeTagInfoCount: 2),
                rangeTagPayload: recoveryRangeTagEntryPayload()
            ),
            expectedFailure: "paragraph range tag count mismatch"
        )
    }

    func testMissingCharShapeBecomesPlaceholderOnlyInRecoverMode() throws {
        try assertMiddleParagraphRecovery(
            corrupt: recoveryParagraphData(
                headerPayload: recoveryParaHeaderPayload(),
                includeCharShape: false
            ),
            expectedFailure: "Record '\(HwpSectionTag.paraCharShape.rawValue)' does not exist",
            expectedDefaultError: { error in
                guard case let HwpError.recordDoesNotExist(tag) = error else {
                    return fail("Expected recordDoesNotExist, got \(error)")
                }
                expect(tag) == HwpSectionTag.paraCharShape.rawValue
            }
        )
    }

    // MARK: - 구역 스트림 구조 손상은 HwpSection.load에서 양 모드 모두 throw

    func testSectionStreamStructureCorruptionThrowsInBothModes() {
        var data = recoveryValidParagraphData(text: 0xAC00)
        data.append(SectionRecordBuilder.record(tagId: 0x2FE, level: 3, payload: Data([0xAA])))

        for options in [HwpLoadOptions.default, recoverOptions] {
            expect {
                _ = try HwpSection.load(data, self.version, options: options)
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("record level 3 has no parent"))
            })
        }
    }

    // MARK: - HwpFile 조립: 구역 실패는 recover 모드에서 placeholder 구역

    func testCorruptSectionBecomesPlaceholderSectionOnlyInRecoverMode() throws {
        let corruptSection = SectionRecordBuilder.record(
            tagId: 0x2FE, level: 2, payload: Data([0xAA])
        )
        let sectionDataArray = [recoveryAssemblySectionData(), corruptSection]

        expect {
            _ = try HwpFile(
                fileHeader: HwpFileHeader(),
                docInfoData: recoveryAssemblyDocInfoData(sectionSize: 2),
                sectionDataArray: sectionDataArray
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 2 has no parent"))
        })

        let recovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: recoveryAssemblyDocInfoData(sectionSize: 2),
            sectionDataArray: sectionDataArray,
            options: recoverOptions
        )

        expect(recovered.sectionArray.count) == 2
        expect(recovered.sectionArray[0].parseFailure).to(beNil())
        expect(recovered.sectionArray[0].paragraph.count) == 1
        let placeholder = recovered.sectionArray[1]
        expect(placeholder.parseFailure).to(contain("record level 2 has no parent"))
        // placeholder 구역은 빈 문서 템플릿 문단으로 조판 전제(sectionDef +
        // column)를 지킨다 — `HwpSection.init()` 재사용을 고정한다.
        expect(placeholder.paragraph.count) == 1
        let templateControls = placeholder.paragraph[0].ctrlHeaderArray
        expect(templateControls?.count) == 2
        guard case .section = templateControls?.first else {
            return fail("Expected placeholder section template to carry sectionDef")
        }
        guard case .column = templateControls?.last else {
            return fail("Expected placeholder section template to carry column")
        }
        expect(placeholder.paragraph[0].parseFailure).to(beNil())
        // 보존 모드에서는 실패한 구역 스트림 원본이 placeholder에 남는다 —
        // 문단 placeholder의 unknownChildren 보존과 대칭인 진단·재파싱 근거.
        expect(placeholder.rawPayload) == corruptSection
        expect(recovered.displaySectionArray.count) == 2

        let viewerRecovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: recoveryAssemblyDocInfoData(sectionSize: 2),
            sectionDataArray: sectionDataArray,
            options: .viewer
        )
        expect(viewerRecovered.sectionArray[1].parseFailure).notTo(beNil())
        expect(viewerRecovered.sectionArray[1].rawPayload).to(beEmpty())
    }

    // MARK: - ViewText 정책: recover 모드에서도 전량 폐기 → BodyText 강등

    func testCorruptViewTextIsDiscardedEntirelyEvenInRecoverMode() throws {
        // 문단 카운트 손상은 recover가 켜져 있으면 placeholder로 "성공" 파싱될
        // 수 있는 입력이다 — ViewText가 이를 채택하면 그 구역이 백지가 되므로,
        // ViewText 경로는 복구 없이 기존 전량 폐기를 유지해야 한다 (#65).
        var corruptHeaderPayload = recoveryParaHeaderPayload(charShapeInfoCount: 2)
        corruptHeaderPayload.append(recoveryLittleEndianData(UInt16(0)))
        let corruptParagraphSection = recoveryParagraphData(
            headerPayload: corruptHeaderPayload,
            charShapePayload: recoveryCharShapePairPayload()
        )
        expect {
            _ = try HwpSection.load(
                corruptParagraphSection, HwpVersion(), options: self.recoverOptions
            )
        }.notTo(throwError())

        let recovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: recoveryAssemblyDocInfoData(sectionSize: 1),
            sectionDataArray: [recoveryAssemblySectionData()],
            viewTextData: [(name: "Section0", data: corruptParagraphSection)],
            options: recoverOptions
        )

        expect(recovered.viewSectionArray).to(beEmpty())
        expect(recovered.sectionArray.count) == 1
        expect(recovered.sectionArray[0].parseFailure).to(beNil())
        expect(recovered.displaySectionArray) == recovered.sectionArray
    }

    func testHealthyViewTextIsStillAdoptedInRecoverMode() throws {
        let recovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: recoveryAssemblyDocInfoData(sectionSize: 1),
            sectionDataArray: [recoveryAssemblySectionData()],
            viewTextData: [(name: "Section0", data: recoveryAssemblySectionData())],
            options: recoverOptions
        )

        expect(recovered.viewSectionArray.count) == 1
        expect(recovered.displaySectionArray) == recovered.viewSectionArray
    }

    // MARK: - FileHeader 차단 계열은 recover 모드에서도 계속 throw

    func testExpectedErrorFixturesStillThrowUnsupportedFeatureInRecoverMode() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError != nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            expect {
                _ = try HwpFile(
                    fromPath: fixture.documentURL.path,
                    options: self.recoverOptions
                )
            }.to(throwError { error in
                guard case HwpError.unsupportedFeature = error else {
                    return fail(
                        "\(fixture.manifest.id): expected unsupportedFeature, got \(error)"
                    )
                }
            })
        }
    }

    // MARK: - 정상 픽스처에서는 placeholder가 절대 생기지 않는다

    func testRecoverModeLeavesHealthyFixturesWithoutAnyPlaceholder() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        // Mirror 재귀로 전수 방문한다 — 최상위·메모뿐 아니라 표 셀·리스트·
        // 글상자 안 중첩 문단의 메모 placeholder까지 스윕 범위에 넣는다.
        var visitedParagraphCount = 0
        for fixture in fixtures {
            let recovered = try HwpFile(
                fromPath: fixture.documentURL.path,
                options: .viewer
            )
            for section in recovered.sectionArray + recovered.viewSectionArray {
                expect(section.parseFailure).to(
                    beNil(),
                    description: "\(fixture.manifest.id) section placeholder must not fire"
                )
                visitedParagraphCount += assertNoParseFailure(
                    in: section, fixture: fixture.manifest.id
                )
            }
        }
        // 공허 gate — 중첩 문단이 실제로 방문됐음을 고정한다 (전 픽스처 합계).
        expect(visitedParagraphCount).to(beGreaterThanOrEqualTo(1000))
    }
}

/// `value` 안의 모든 `HwpParagraph`(임의 깊이 — 컨트롤·메모 그룹 포함)를
/// Mirror로 재귀 방문해 parseFailure 부재를 단언하고, 방문 수를 돌려준다.
private func assertNoParseFailure(in value: Any, fixture fixtureId: String) -> Int {
    var visited = 0
    // charArray는 문서 전체 문자 수만큼 있다 — 문단이 나올 수 없으니 걷지 않는다.
    if value is Data || value is HwpChar || value is [HwpChar] {
        return 0
    }
    if let paragraph = value as? HwpParagraph {
        visited += 1
        expect(paragraph.parseFailure).to(
            beNil(),
            description: "\(fixtureId) paragraph placeholder must not fire"
        )
    }
    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        visited += assertNoParseFailure(in: child.value, fixture: fixtureId)
    }
    return visited
}

// MARK: - 공통 단언

private extension ParagraphRecoveryPlaceholderTests {
    /// 정상 문단("가") + 손상 문단 + 정상 문단("나") 구역 스트림으로,
    /// default 모드의 typed throw와 recover 모드의 placeholder 대체·이웃
    /// 보존을 함께 고정한다.
    func assertMiddleParagraphRecovery(
        corrupt: Data,
        expectedFailure: String,
        expectedDefaultError: ((Error) -> Void)? = nil
    ) throws {
        var data = recoveryValidParagraphData(text: 0xAC00)
        data.append(corrupt)
        data.append(recoveryValidParagraphData(text: 0xB098))

        expect {
            _ = try HwpSection.load(data, self.version)
        }.to(throwError { error in
            if let expectedDefaultError {
                expectedDefaultError(error)
            } else {
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain(expectedFailure))
            }
        })

        let section = try HwpSection.load(data, version, options: recoverOptions)

        expect(section.parseFailure).to(beNil())
        expect(section.paragraph.count) == 3
        expect(section.paragraph[0].parseFailure).to(beNil())
        expect(section.paragraph[0].paraText?.charArray.map(\.value)) == [0xAC00]
        expect(section.paragraph[2].parseFailure).to(beNil())
        expect(section.paragraph[2].paraText?.charArray.map(\.value)) == [0xB098]

        let placeholder = section.paragraph[1]
        expect(placeholder.parseFailure).to(contain(expectedFailure))
        expect(placeholder.paraText).to(beNil())
        expect(placeholder.ctrlHeaderArray).to(beNil())
        expect(placeholder.unknownChildren.count) == 1
        expect(placeholder.unknownChildren.first?.tagId) == HwpSectionTag.paraHeader.rawValue
    }
}

// MARK: - 합성 스트림 빌더 (프레이밍은 SectionRecordBuilder 위임)

private func recoveryValidParagraphData(text: WCHAR) -> Data {
    recoveryParagraphData(
        headerPayload: recoveryParaHeaderPayload(charCount: 1),
        paraTextPayload: recoveryLittleEndianData(text)
    )
}

private func recoveryParagraphData(
    headerPayload: Data,
    paraTextPayload: Data? = nil,
    charShapePayload: Data = Data(),
    includeCharShape: Bool = true,
    lineSegPayload: Data = Data(),
    rangeTagPayload: Data? = nil
) -> Data {
    var data = SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: headerPayload
    )
    if let paraTextPayload {
        data.append(SectionRecordBuilder.record(
            tagId: HwpSectionTag.paraText.rawValue,
            level: 1,
            payload: paraTextPayload
        ))
    }
    if includeCharShape {
        data.append(SectionRecordBuilder.record(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: charShapePayload
        ))
    }
    data.append(SectionRecordBuilder.record(
        tagId: HwpSectionTag.paraLineSeg.rawValue,
        level: 1,
        payload: lineSegPayload
    ))
    if let rangeTagPayload {
        data.append(SectionRecordBuilder.record(
            tagId: HwpSectionTag.paraRangeTag.rawValue,
            level: 1,
            payload: rangeTagPayload
        ))
    }
    return data
}

/// PARA_HEADER payload (5.0.1.1 — isTraceChange 없음, 22 byte).
/// 카운트 필드 오프셋: charCount 0-3, charShapeInfoCount 12-13,
/// rangeTagInfoCount 14-15, alignInfoCount 16-17 (`HwpParaHeader` 읽기 순서).
private func recoveryParaHeaderPayload(
    charCount: UInt32 = 0,
    charShapeInfoCount: UInt16 = 0,
    rangeTagInfoCount: UInt16 = 0,
    alignInfoCount: UInt16 = 0
) -> Data {
    var data = Data()
    data.append(recoveryLittleEndianData(charCount | 0x8000_0000))
    data.append(recoveryLittleEndianData(UInt32(0)))
    data.append(recoveryLittleEndianData(UInt16(0)))
    data.append(recoveryLittleEndianData(UInt8(0)))
    data.append(recoveryLittleEndianData(UInt8(0)))
    data.append(recoveryLittleEndianData(charShapeInfoCount))
    data.append(recoveryLittleEndianData(rangeTagInfoCount))
    data.append(recoveryLittleEndianData(alignInfoCount))
    data.append(recoveryLittleEndianData(UInt32(1)))
    return data
}

private func recoveryCharShapePairPayload() -> Data {
    concatenatedData(
        recoveryLittleEndianData(UInt32(0)),
        recoveryLittleEndianData(UInt32(0))
    )
}

private func recoveryLineSegEntryPayload() -> Data {
    var data = Data()
    data.append(recoveryLittleEndianData(UInt32(0)))
    data.append(recoveryLittleEndianData(Int32(100)))
    data.append(recoveryLittleEndianData(Int32(1000)))
    data.append(recoveryLittleEndianData(Int32(1000)))
    data.append(recoveryLittleEndianData(Int32(850)))
    data.append(recoveryLittleEndianData(Int32(600)))
    data.append(recoveryLittleEndianData(Int32(0)))
    data.append(recoveryLittleEndianData(Int32(42520)))
    data.append(recoveryLittleEndianData(UInt32(393_216)))
    return data
}

private func recoveryRangeTagEntryPayload() -> Data {
    concatenatedData(
        recoveryLittleEndianData(UInt32(1)),
        recoveryLittleEndianData(UInt32(9)),
        recoveryLittleEndianData(UInt32(0xABCD))
    )
}

// MARK: - HwpFile 조립 최소 입력 (HwpFileHeader() 버전 5.1.0.1 기준)

private func recoveryAssemblyDocInfoData(sectionSize: UInt16) -> Data {
    concatenatedData(
        SectionRecordBuilder.record(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: concatenatedData(
                recoveryLittleEndianData(sectionSize),
                Data(repeating: 0, count: 24)
            )
        ),
        SectionRecordBuilder.record(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
                data.append(recoveryLittleEndianData(count))
            }
        )
    )
}

/// 5.0.3.2 이상 버전용 24 byte PARA_HEADER를 가진 최소 정상 구역.
private func recoveryAssemblySectionData() -> Data {
    var headerPayload = recoveryParaHeaderPayload(charShapeInfoCount: 1)
    headerPayload.append(recoveryLittleEndianData(UInt16(0)))
    return concatenatedData(
        SectionRecordBuilder.record(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: headerPayload
        ),
        SectionRecordBuilder.record(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: recoveryCharShapePairPayload()
        )
    )
}

private func recoveryLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    SectionRecordBuilder.littleEndian(value)
}
