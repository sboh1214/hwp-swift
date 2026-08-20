@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 뷰어 모드(`.viewer`)에서 파싱된 구역 모델의 **모든 `Data` leaf**가 압축
/// 해제 스트림 버퍼 밖(분리 복사 또는 empty)임을 Mirror 기반 재귀 walker로
/// 단언한다 (#67).
///
/// `RawPayloadOptOutTests`는 손으로 유지하는 대표 필드 목록만 보므로, 새
/// 모델 필드가 `decoupledPayload`/`preservedPayload` 게이트를 빠뜨려도
/// 잡히지 않는다 — 이 walker가 그 사각을 막는다. 원본 버퍼는 default 모드
/// 로드가 보존한 `section.rawPayload`(구역 스트림 원본)를 재사용한다.
final class ViewerPayloadDecouplingTests: XCTestCase {
    func testViewerSectionModelsDoNotAliasSourceStreamBuffer() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        var inspectedLeafCount = 0
        for fixture in fixtures {
            let preserved = try HwpFile(fromPath: fixture.documentURL.path)
            for (index, section) in preserved.sectionArray.enumerated() {
                let source = section.rawPayload
                guard !source.isEmpty else { continue }
                let viewerSection = try HwpSection.load(
                    source,
                    preserved.fileHeader.version,
                    options: .viewer
                )

                inspectedLeafCount += assertNoDataLeafAliases(
                    source: source,
                    in: viewerSection,
                    path: "\(fixture.manifest.id).section[\(index)]"
                )
            }
        }
        // 공허 gate — walker가 아무 leaf도 방문하지 않은 채 초록이 되는 것을
        // 막는다. 픽스처는 늘어나는 방향으로만 움직인다.
        expect(inspectedLeafCount).to(beGreaterThanOrEqualTo(100))
    }

    /// DocInfo 스트림 모델도 같은 walker로 덮는다 — 손 목록
    /// (`RawPayloadOptOutTests`의 docInfo 최상위 필드 +
    /// `DocInfoRawRecordViewerOptOutTests`의 raw record 6종)이 못 보는
    /// DocInfo 하위 모델의 새 `Data` 필드가 게이트를 빠뜨리면 여기서 잡힌다.
    func testViewerDocInfoModelsDoNotAliasSourceStreamBuffer() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        var inspectedLeafCount = 0
        for fixture in fixtures {
            let preserved = try HwpFile(fromPath: fixture.documentURL.path)
            let source = preserved.docInfo.rawPayload
            guard !source.isEmpty else { continue }
            let viewerDocInfo = try HwpDocInfo.load(
                source,
                preserved.fileHeader.version,
                options: .viewer
            )

            inspectedLeafCount += assertNoDataLeafAliases(
                source: source,
                in: viewerDocInfo,
                path: "\(fixture.manifest.id).docInfo"
            )
        }
        // DocInfo는 구역보다 비어 있지 않은 Data leaf가 적다 (뷰어 모드가
        // 보존 슬라이스를 비우므로) — 현 픽스처 실측 58, 여유를 두고 40.
        expect(inspectedLeafCount).to(beGreaterThanOrEqualTo(40))
    }
}

/// `value` 안의 모든 비어 있지 않은 `Data` leaf를 재귀 방문해 `source`
/// 버퍼와의 겹침을 단언하고, 방문한 leaf 수를 돌려준다.
private func assertNoDataLeafAliases(source: Data, in value: Any, path: String) -> Int {
    var inspected = 0
    walkDataLeaves(of: value, path: path) { leaf, leafPath in
        inspected += 1
        expect(aliases(leaf, source: source)).to(
            beFalse(),
            description: "\(leafPath) must not alias the decompressed section buffer"
        )
    }
    return inspected
}

private func walkDataLeaves(
    of value: Any,
    path: String,
    visit: (Data, String) -> Void
) {
    if let data = value as? Data {
        if !data.isEmpty {
            visit(data, path)
        }
        return
    }
    // charArray는 문서 전체 문자 수만큼 있다 — Mirror 없이 payload만 본다.
    if let char = value as? HwpChar {
        if let payload = char.payload, !payload.isEmpty {
            visit(payload, "\(path).payload")
        }
        return
    }
    if let chars = value as? [HwpChar] {
        for (index, char) in chars.enumerated() {
            walkDataLeaves(of: char, path: "\(path)[\(index)]", visit: visit)
        }
        return
    }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == nil, mirror.children.isEmpty {
        return
    }
    for (index, child) in mirror.children.enumerated() {
        let label = child.label ?? "[\(index)]"
        walkDataLeaves(of: child.value, path: "\(path).\(label)", visit: visit)
    }
}

private func aliases(_ leaf: Data, source: Data) -> Bool {
    source.withUnsafeBytes { sourceBuffer -> Bool in
        guard let sourceBase = sourceBuffer.baseAddress, !sourceBuffer.isEmpty else {
            return false
        }
        return leaf.withUnsafeBytes { leafBuffer -> Bool in
            guard let leafBase = leafBuffer.baseAddress, !leafBuffer.isEmpty else {
                return false
            }
            return leafBase >= sourceBase
                && leafBase < sourceBase + sourceBuffer.count
        }
    }
}
