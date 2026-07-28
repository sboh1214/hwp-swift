@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 조작 문서의 깊은 중첩이 typed 디코더 재귀(표 셀 문단·리스트 컨트롤·글상자
/// 문단·메모)를 타고 catch 불가능한 스택 오버플로로 번지지 않도록,
/// `parseTreeRecord` 단일 지점이 레코드 level을 상한하는지 검증한다.
///
/// `parentIndex = Int(level)` + 스택 절단/append 방식이라 `record.level ==
/// 실제 트리 깊이` 불변식이 성립하고, typed 재귀는 전부 자식(level 증가)
/// 방향으로만 내려가므로 이 한 지점의 가드가 모든 재귀를 함께 상한한다.
final class RecordDepthLimitTests: XCTestCase {
    private func options(maxNestingDepth: Int) -> HwpLoadOptions {
        HwpLoadOptions(readLimits: HwpReadLimits(maxNestingDepth: maxNestingDepth))
    }

    /// 한 줄로 이어진 체인의 최말단 level. 체인이 아니면 nil.
    private func deepestLevel(of root: HwpRecord) -> UInt32? {
        var node = root
        var level: UInt32?
        while let child = node.children.first {
            guard node.children.count == 1 else { return nil }
            level = child.level
            node = child
        }
        return level
    }

    // MARK: - 한도 경계

    func testChainAtLimitDepthParses() throws {
        let data = SectionRecordBuilder.nestedChain(depth: 8)

        let root = try parseTreeRecord(data: data, options: options(maxNestingDepth: 8))

        expect(self.deepestLevel(of: root)) == 7
    }

    func testChainExceedingLimitThrowsTypedError() {
        let data = SectionRecordBuilder.nestedChain(depth: 9)
        let options = options(maxNestingDepth: 8)

        expect {
            _ = try parseTreeRecord(data: data, options: options)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 8 exceeds max nesting depth 8"))
        })
    }

    func testRaisedLimitAcceptsPreviouslyRejectedDepth() throws {
        let data = SectionRecordBuilder.nestedChain(depth: 9)

        let root = try parseTreeRecord(data: data, options: options(maxNestingDepth: 16))

        expect(self.deepestLevel(of: root)) == 8
    }

    // MARK: - 기본 한도(64)

    func testDefaultLimitAcceptsChainAtDepth64() throws {
        let root = try parseTreeRecord(data: SectionRecordBuilder.nestedChain(depth: 64))

        expect(self.deepestLevel(of: root)) == 63
    }

    func testDefaultLimitRejectsChainAtDepth65() {
        let data = SectionRecordBuilder.nestedChain(depth: 65)

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds max nesting depth 64"))
        })
    }

    // MARK: - 할당 유도 차단 (payload·확장 크기를 읽기 전에 거부)

    func testDepthLimitIsRejectedBeforeExtendedSizeRead() {
        // 확장 크기 sentinel만 있고 뒤따르는 UInt32가 없다 — 깊이 가드가
        // 먼저 걸리지 않으면 truncatedData가 난다.
        var data = SectionRecordBuilder.nestedChain(depth: 8)
        data.append(SectionRecordBuilder.header(tagId: 16, level: 8, size: 0xFFF))
        let options = options(maxNestingDepth: 8)

        expect {
            _ = try parseTreeRecord(data: data, options: options)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds max nesting depth"))
        })
    }

    func testDepthLimitIsRejectedBeforePayloadRead() {
        // 확장 크기가 UInt32.max — 깊이 가드가 먼저 걸리지 않으면 거대
        // payload 읽기를 시도한다.
        var data = SectionRecordBuilder.nestedChain(depth: 8)
        data.append(SectionRecordBuilder.header(tagId: 16, level: 8, size: 0xFFF))
        data.append(SectionRecordBuilder.littleEndian(UInt32.max))
        let options = options(maxNestingDepth: 8)

        expect {
            _ = try parseTreeRecord(data: data, options: options)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds max nesting depth"))
        })
    }

    // MARK: - 기존 level 가드와의 우선순위

    func testMissingParentStillReportsParentReasonWithinDepthLimit() {
        // level 2인데 부모가 없다 — 깊이 한도 안이므로 기존 진단이 유지된다.
        let data = SectionRecordBuilder.header(tagId: 16, level: 2, size: 0)

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 2 has no parent"))
        })
    }

    // MARK: - 공개 진입점 강제 (typed 디코더를 먹이는 경로)

    /// 나머지 테스트는 `parseTreeRecord`를 직접 부르지만, 실제로 typed 재귀를
    /// 구동하는 것은 `HwpSection.load`다. 태그도 `paraHeader`(66)로 두어
    /// "가드가 typed 디코더에 닿기 전에 공개 경로에서 발동한다"를 고정한다 —
    /// 누군가 옵션 전파를 끊거나 파스 경로를 우회하면 여기서 깨진다.
    func testSectionLoadEnforcesDepthLimitOnPublicEntryPoint() {
        let data = SectionRecordBuilder.nestedChain(
            depth: 9, tagId: HwpSectionTag.paraHeader.rawValue
        )
        let options = options(maxNestingDepth: 8)

        expect {
            _ = try HwpSection.load(data, HwpVersion(5, 0, 3, 0), options: options)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds max nesting depth"))
        })
    }

    /// `HwpFile` 이니셜라이저와 달리 이 경로로는 검증되지 않은 한도가 들어온다.
    func testSectionLoadRejectsNonPositiveNestingDepthWithTypedError() {
        let data = SectionRecordBuilder.nestedChain(
            depth: 1, tagId: HwpSectionTag.paraHeader.rawValue
        )
        let options = options(maxNestingDepth: 0)

        expect {
            _ = try HwpSection.load(data, HwpVersion(5, 0, 3, 0), options: options)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length).to(contain("maxNestingDepth"))
        })
    }

    // MARK: - 실문서 오탐 방지

    /// 정상 문서가 한도 근처에도 가지 않음을 고정한다. 실측 최대 level은 5이며
    /// 8로 잠가 두면 기본값 64가 12배 이상 여유임이 회귀로 보장된다.
    func testEveryReadableFixtureParsesUnderTightNestingDepth() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            do {
                _ = try HwpFile(
                    fromPath: fixture.documentURL.path,
                    readLimits: HwpReadLimits(maxNestingDepth: 8)
                )
            } catch {
                fail("fixture \(fixture.manifest.id) failed under maxNestingDepth 8: \(error)")
            }
        }
    }

    /// 위 테스트가 공허하지 않음을 고정한다 — 실문서의 typed 중첩(표 셀 문단·
    /// 컨트롤 리스트)이 실제로 level을 소비하므로, 한도를 2로 낮추면 표가 있는
    /// 픽스처는 열리지 않는다. 즉 한도 8 통과는 "가드가 꺼져 있어서"가 아니다.
    func testNestedFixtureIsRejectedUnderMinimalNestingDepth() throws {
        let fixture = try FixtureLoader.load(id: "noori")

        expect {
            _ = try HwpFile(
                fromPath: fixture.documentURL.path,
                readLimits: HwpReadLimits(maxNestingDepth: 2)
            )
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds max nesting depth 2"))
        })
    }
}
