import Foundation

/// `hh:compatibleDocument` → `HwpDocInfo.compatibleDocument` (#187).
extension HwpxHeaderMapper {
    /// 잘못된 `targetProgram` 이름을 진단으로 남길 때의 합성 레코드 payload 접두 —
    /// 속성 강등이라 `요소@속성=값` 꼴이다 (`secPr@outlineShapeIDRef=`와 같다).
    static let targetProgramDiagnosticPrefix = "compatibleDocument@targetProgram="

    /// `hh:compatibleDocument` → `HwpCompatibleDocument` (#187).
    ///
    /// 옮기는 것은 `@targetProgram` 하나다 — 표 55의 값이 조판·렌더링의 분기 축이라
    /// (MS 워드 호환 문서의 장식선 기하) 강등 상태로 두면 같은 문서가 HWP로 열 때와
    /// HWPX로 열 때 다르게 그려진다. 이름은 한컴 모델 `g_CompatiblieDocList` 그대로이고
    /// **생략은 `HWP201X`**(한컴 참조 모델의 생성자 기본값 `CT_HWP201X`, `GetAttribute`는
    /// 속성 부재 시 값을 건드리지 않는다), **미지 이름**도 `HWP201X`로 접되 속성 강등
    /// 진단을 남겨 생략과 구분한다. 자식(`hh:layoutCompatibility`의 35개 불리언 요소 등)은
    /// 표 56 비트로 옮기는 표가 없어 전부 `unknownChildren`으로 강등한다 — 한글은 이
    /// 플래그로 장식선 기하를 바꾸지 않으므로 (#187 실측) 렌더에는 영향이 없다.
    static func mapCompatibleDocument(
        _ node: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) -> HwpCompatibleDocument {
        var diagnostics: [HwpUnknownRecord] = []
        var target = HwpCompatibleDocumentTarget.hwp201X
        if let name = node.attribute("targetProgram") {
            if let known = HwpCompatibleDocumentTarget(owpmlName: name) {
                target = known
            } else {
                diagnostics.append(HwpUnknownRecord(
                    tagId: hwpxSyntheticTagId,
                    level: 0,
                    payload: Data((targetProgramDiagnosticPrefix + name).utf8)
                ))
            }
        }
        diagnostics += node.unconsumedChildRecords(
            consumed: [], maxDepth: mapping.unknownDepthLimit
        )
        return HwpCompatibleDocument(hwpxTarget: target, unknownChildren: diagnostics)
    }
}
