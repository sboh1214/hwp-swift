@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 메모(MEMO_LIST 93) 재귀 파싱의 정상 경로·경계·복구 시맨틱 고정 (#67).
///
/// 재귀 깊이 자체는 파스 시점 가드(`HwpRecord.parseTreeRecord`의
/// `maxNestingDepth`, #64)가 상한하고 `RecordDepthLimitTests`가 경계를
/// 커버한다 — 렌더 측 `HwpPaginator.maximumContainerDepth = 3`은 **배치
/// 재귀**(컨테이너 중첩)의 별도 한도라 파서 한도와 의미가 다르며, 초과분은
/// 파싱은 되고 진단(`unsupportedElements`)으로만 보고된다. 여기서는 메모
/// 그룹 경계와 recover 모드(#65)의 placeholder 대체만 다룬다.
final class ParagraphMemoRecursionTests: XCTestCase {
    private let version = HwpVersion(5, 0, 1, 1)

    func testSingleMemoWithMultipleParagraphsKeepsGroupBoundary() throws {
        let host = memoHostParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xAC00),
            memoParagraphRecord(text: 0xB098),
        ])

        let paragraph = try HwpParagraph.load(host, version)

        expect(paragraph.memoParagraphGroups?.count) == 1
        expect(paragraph.memoParagraphGroups?.first?.count) == 2
        expect(
            paragraph.memoParagraphGroups?.first?
                .map { $0.paraText?.charArray.map(\.value) ?? [] }
        ) == [[0xAC00], [0xB098]]
        expect(paragraph.memoParagraphArray?.count) == 2
        // MEMO_LIST와 그 문단들은 소비된 것으로 처리되어 unknownChildren에
        // 남지 않는다.
        expect(paragraph.unknownChildren).to(beEmpty())
    }

    func testMultipleMemosSplitIntoSeparateGroups() throws {
        let host = memoHostParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xAC00),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xB098),
            memoParagraphRecord(text: 0xB2E4),
        ])

        let paragraph = try HwpParagraph.load(host, version)

        expect(paragraph.memoParagraphGroups?.count) == 2
        expect(paragraph.memoParagraphGroups?.map(\.count)) == [1, 2]
        // 평탄 배열은 그룹의 flatMap이다.
        expect(paragraph.memoParagraphArray?.count) == 3
    }

    func testMemoListWithoutParagraphsKeepsEmptyGroupAndNilFlatArray() throws {
        let host = memoHostParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
        ])

        let paragraph = try HwpParagraph.load(host, version)

        // 문단 없는 메모: 그룹은 빈 배열 하나, 평탄 배열은 nil — 현행 시맨틱 고정.
        expect(paragraph.memoParagraphGroups?.count) == 1
        expect(paragraph.memoParagraphGroups?.first).to(beEmpty())
        expect(paragraph.memoParagraphArray).to(beNil())
        // MEMO_LIST는 빈 그룹으로 typed 소비됐으므로 unknownChildren에
        // 중복 보존되지 않는다 (#66 — 소비 인덱스 기반 제외).
        expect(paragraph.unknownChildren).to(beEmpty())
    }

    func testStrayParagraphBeforeFirstMemoListIsPreservedAsUnknownChild() throws {
        // 첫 MEMO_LIST 앞의 문단(66) child는 그룹 빌더가 소비하지 않는다
        // (current == nil). 태그 blanket 제외 시절에는 이 record가 typed 소비도
        // raw 보존도 없이 모델에서 사라져 미해석 집계(#66)가 볼 수 없었다 —
        // 소비 인덱스 기반 제외로 unknownChildren에 남는지 고정한다.
        let host = memoHostParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xAC00),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xB098),
        ])

        let paragraph = try HwpParagraph.load(host, version)

        expect(paragraph.memoParagraphGroups?.count) == 1
        expect(
            paragraph.memoParagraphGroups?.first?
                .map { $0.paraText?.charArray.map(\.value) ?? [] }
        ) == [[0xB098]]
        expect(paragraph.unknownChildren.count) == 1
        expect(paragraph.unknownChildren.first?.tagId) == HwpSectionTag.paraHeader.rawValue
    }

    func testCorruptMemoParagraphThrowsTypedErrorInDefaultMode() {
        // default 모드: 손상 메모 문단은 호스트 문단 전체를 실패시킨다.
        let corruptDefault = memoHostParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()),
            memoParagraphRecord(text: 0xAC00),
            corruptMemoParagraphRecord(),
        ])

        expect {
            _ = try HwpParagraph.load(corruptDefault, self.version)
        }.to(throwError { error in
            guard case let HwpError.recordDoesNotExist(tag) = error else {
                return fail("Expected recordDoesNotExist, got \(error)")
            }
            expect(tag) == HwpSectionTag.paraCharShape.rawValue
        })
    }

    func testCorruptMemoParagraphBecomesPlaceholderInRecoverMode() throws {
        // recover 모드: 손상 메모 문단만 placeholder로 바뀌고 그룹 경계·호스트는
        // 보존된다 (#65).
        let recoverOptions = HwpLoadOptions(recoverPartialContent: true)
        let corruptRecover = memoHostParagraphRecord(
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data(),
                    options: recoverOptions
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data(),
                    options: recoverOptions
                ),
                HwpRecord(
                    tagId: HwpSectionTag.memoList.rawValue,
                    level: 1,
                    payload: Data(),
                    options: recoverOptions
                ),
                memoParagraphRecord(text: 0xAC00, options: recoverOptions),
                corruptMemoParagraphRecord(options: recoverOptions),
            ],
            options: recoverOptions
        )

        let paragraph = try HwpParagraph.load(corruptRecover, version)

        expect(paragraph.parseFailure).to(beNil())
        expect(paragraph.memoParagraphGroups?.count) == 1
        let group = try XCTUnwrap(paragraph.memoParagraphGroups?.first)
        expect(group.count) == 2
        expect(group[0].parseFailure).to(beNil())
        expect(group[0].paraText?.charArray.map(\.value)) == [0xAC00]
        expect(group[1].parseFailure).to(
            contain("Record '\(HwpSectionTag.paraCharShape.rawValue)' does not exist")
        )
        expect(group[1].paraText).to(beNil())
        expect(group[1].unknownChildren.count) == 1
        expect(group[1].unknownChildren.first?.tagId) == HwpSectionTag.paraHeader.rawValue
    }
}

private func memoHostParagraphRecord(
    children: [HwpRecord],
    options: HwpLoadOptions = .default
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: memoParagraphHeaderPayload(charCount: 0),
        options: options
    )
    record.children = children
    return record
}

private func memoParagraphRecord(
    text: WCHAR,
    options: HwpLoadOptions = .default
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 1,
        payload: memoParagraphHeaderPayload(charCount: 1),
        options: options
    )
    record.children = [
        HwpRecord(
            tagId: HwpSectionTag.paraText.rawValue,
            level: 2,
            payload: memoLittleEndianData(text),
            options: options
        ),
        HwpRecord(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 2,
            payload: Data(),
            options: options
        ),
        HwpRecord(
            tagId: HwpSectionTag.paraLineSeg.rawValue,
            level: 2,
            payload: Data(),
            options: options
        ),
    ]
    return record
}

/// 필수 PARA_CHAR_SHAPE가 없는 메모 문단 — recordDoesNotExist를 던진다.
private func corruptMemoParagraphRecord(options: HwpLoadOptions = .default) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 1,
        payload: memoParagraphHeaderPayload(charCount: 0),
        options: options
    )
    record.children = [
        HwpRecord(
            tagId: HwpSectionTag.paraLineSeg.rawValue,
            level: 2,
            payload: Data(),
            options: options
        ),
    ]
    return record
}

private func memoParagraphHeaderPayload(charCount: UInt32) -> Data {
    var data = Data()
    data.append(memoLittleEndianData(charCount | 0x8000_0000))
    data.append(memoLittleEndianData(UInt32(0)))
    data.append(memoLittleEndianData(UInt16(0)))
    data.append(memoLittleEndianData(UInt8(0)))
    data.append(memoLittleEndianData(UInt8(0)))
    data.append(memoLittleEndianData(UInt16(0)))
    data.append(memoLittleEndianData(UInt16(0)))
    data.append(memoLittleEndianData(UInt16(0)))
    data.append(memoLittleEndianData(UInt32(1)))
    return data
}

private func memoLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
