import CoreHwp
import Foundation

/// 개요(문단 머리 종류 1)·번호 매기기(종류 2) 문단이 참조하는 번호 정의의
/// 해석 (#152).
///
/// 두 종류는 정의를 **다른 곳**에서 찾는다. 번호 매기기는 문단 모양의
/// `numberingOrBulletId`(1-based, 0 = 없음)이고, 개요는 그 값이 실문서에서 전부
/// 0이라 (헌법주석 개요 1,944문단) 구역 정의의 `HwpSectionDef.numberParaShapeId`
/// (역시 1-based)를 따른다 — 종전 진단은 두 종류 모두 문단 모양의 값만 봐
/// 개요 문단을 한 건도 잡지 못했다. 둘 다 1을 빼 0-based `HwpIndex.numbering(id:)`
/// 에 넘긴다.
///
/// 이 타입은 조판과 무관한 순수 함수라 픽스처 테스트가 1,030쪽을 배치하지 않고
/// 문단을 걸어 검증한다 (`HwpOutlineCollector`를 직접 모는 것과 같은 방식).
/// 진단 문자열(`unsupportedHint`)의 집계 단위는 **문단**이다 — 문단마다 한 건이고
/// 쪽은 그 문단이 시작한 쪽이다 (`HwpPaginator.collectUnsupportedNumberingHeading`).
/// 글머리표(종류 3)는 `appendBulletHeading`이 그리므로 대상이 아니다(nil).
struct HwpNumberingHeadingReference: Equatable {
    /// 문단 머리 종류 (표 44 bit 23-24).
    enum Kind: Equatable {
        /// 1 — 구역 정의의 개요 번호 정의를 쓴다.
        case outline
        /// 2 — 문단 모양의 번호 정의를 쓴다.
        case numbering
    }

    /// 참조가 닿은 곳.
    enum Definition: Equatable {
        /// 정의 배열 안 — `HwpIndex.numbering(id:)`의 0-based 키.
        case resolved(index: UInt32)
        /// 참조 값 0 — 정의를 가리키지 않는다.
        case none
        /// 1-based 참조가 정의 배열 밖이다 (댕글링).
        case dangling(id: UInt16)
    }

    let kind: Kind
    /// 사람이 읽는 수준 (1-기반) — 저장값(표 44 bit 25-27)에 1을 더한 값.
    let level: Int
    let definition: Definition

    /// 문단 모양·현재 구역 정의·정의 사전으로 참조를 푼다. 문단 머리가 개요·
    /// 번호가 아니면 nil.
    ///
    /// `sectionDef`가 nil이면 (구역 정의 없는 합성 문서) 개요는 참조 없음이다 —
    /// 빈 문서 기본값 1을 지어내면 정의가 없는 문서에서 댕글링 진단이 잘못 선다.
    static func resolve(
        paraShape: CoreHwp.HwpParaShape,
        sectionDef: CoreHwp.HwpSectionDef?,
        index: HwpIndex
    ) -> HwpNumberingHeadingReference? {
        let kind: Kind
        let referenceId: UInt16
        switch paraShape.property1Info.headingTypeRawValue {
        case 1:
            kind = .outline
            referenceId = sectionDef?.numberParaShapeId ?? 0
        case 2:
            kind = .numbering
            referenceId = paraShape.numberingOrBulletId
        default:
            return nil
        }
        let definition: Definition = if referenceId == 0 {
            .none
        } else if index.numbering(id: UInt32(referenceId) - 1) != nil {
            .resolved(index: UInt32(referenceId) - 1)
        } else {
            .dangling(id: referenceId)
        }
        return HwpNumberingHeadingReference(
            kind: kind,
            level: Int(paraShape.property1Info.headingLevelRawValue) + 1,
            definition: definition
        )
    }

    /// 참조가 닿은 번호 정의 — `resolved`일 때만.
    func numbering(in index: HwpIndex) -> CoreHwp.HwpNumbering? {
        guard case let .resolved(definitionIndex) = definition else { return nil }
        return index.numbering(id: definitionIndex)
    }

    /// 이 수준의 번호 형식 — 정의가 닿고 그 수준 슬롯이 있을 때만.
    func format(in index: HwpIndex) -> CoreHwp.HwpNumberingFormat? {
        numbering(in: index)?.format(forLevel: level)
    }

    /// `unsupportedElements()`에 실을 진단 문자열.
    ///
    /// 정의에 닿은 문단은 종전 문구 "(미렌더)"를 그대로 쓴다 — 라벨을 렌더러가
    /// 아직 만들지 않는다는 뜻이고 #154가 렌더한 문단을 여기서 뺀다. 참조가
    /// 없거나 댕글링이면 라벨을 만들 정의 자체가 없으므로 그 사실을 적는다.
    var unsupportedHint: String {
        let subject = switch kind {
        case .outline: "개요 번호 문단 머리"
        case .numbering: "번호 매기기 문단 머리"
        }
        return switch definition {
        case .resolved: "\(subject) (미렌더)"
        case .none: "\(subject) (번호 정의 참조 없음)"
        case let .dangling(id): "\(subject) (없는 번호 정의 \(id) 참조)"
        }
    }
}
