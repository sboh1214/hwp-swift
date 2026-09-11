@testable import CoreHwp
import Foundation

/// 구역 정의 설정 등가 투영 (#173) — `DocumentEquivalenceProjection`의 구역 설정 축.
///
/// 본체에서 떼어 둔 것은 이 축이 `HwpSectionDef`의 **속성 bit field와 시작 번호
/// 필드를 함께** 읽기 때문이다 — 다른 구역 축(`pageGeometries`·
/// `sectionOutlineNumberingIds`·`noteShapes`)은 값 하나씩만 보지만, 여기서는
/// 표 130 bit field의 파생 필드가 축의 일부다. 구역 정의에서 오는 종전 축이
/// 용지·여백·개요 번호 참조·주석 모양만 봐서 `hp:startNum@pageStartsOn`의
/// 홀수·짝수가 뒤바뀐 매핑도 등가 스위트를 통과했다 (#173).
extension DocumentEquivalenceProjection {
    /// 구역 정의 하나의 시작 설정(표 129 시작 번호 필드)과 첫 쪽 감추기(표 130 비트).
    ///
    /// **HWPX 매퍼가 옮기는 필드만 싣는다** — 예약 비트를 포함한 원시 값 전체를
    /// 비교하면 한쪽 저작기가 예약 비트를 채우는 순간 유효한 쌍이 깨진다. 실려
    /// 있지 않은 것: 텍스트 방향(bits 16-18)·빈 줄 감추기(bit 19)·원고지 정서법
    /// (bit 22)·테두리/배경 감추기(bits 3·4·8·9). `HwpxSecPrMapper`가
    /// `hp:secPr@textDirection`·`hp:visibility@hideFirstEmptyLine`·`@border`·`@fill`·
    /// `hp:grid@wonggojiFormat`을 아직 옮기지 않고 실물 표본도 없어, 넣어도 두
    /// 포맷이 함께 0인 등식만 남기 때문이다 — 그 매핑을 승격할 때 실측과 함께
    /// 이 축에 넣는다.
    struct SectionSettings: Equatable {
        /// 표 130 bits 20-21 — 구역 나눔으로 새 쪽이 생길 때의 쪽 번호 적용 방식
        /// (0 이어서 · 1 짝수 · 2 홀수). HWPX `pageStartsOn`의 `EVEN`·`ODD`가
        /// 이 값으로 옮겨져야 HWP 쌍과 같다.
        let pageStartsOn: Int
        /// 사용자 지정 시작 쪽 번호 (0 = 앞 구역에 이어).
        let pageStartNumber: UInt16
        /// 사용자 지정 시작 그림 번호 (0 = 앞 구역에 이어).
        let pictureStartNumber: UInt16
        /// 사용자 지정 시작 표 번호 (0 = 앞 구역에 이어).
        let tableStartNumber: UInt16
        /// 사용자 지정 시작 수식 번호 (0 = 앞 구역에 이어).
        let equationNumber: UInt16
        /// 구역 첫 쪽 머리말 감추기 — 표 130 bit 0 (`hp:visibility@hideFirstHeader`, #167).
        let hidesFirstHeader: Bool
        /// 구역 첫 쪽 꼬리말 감추기 — 표 130 bit 1 (`@hideFirstFooter`).
        let hidesFirstFooter: Bool
        // swiftlint:disable inclusive_language
        /// 구역 첫 쪽 바탕쪽 감추기 — 표 130 bit 2 (`@hideFirstMasterPage`).
        let hidesFirstMasterPage: Bool
        // swiftlint:enable inclusive_language
        /// 구역 첫 쪽 쪽 번호 감추기 — 표 130 bit 5 (`@hideFirstPageNum`).
        let hidesFirstPageNumber: Bool
    }

    /// 구역마다 구역 정의의 시작 설정을 모은다 (#173). 구역 첫 문단의 첫 `.section`
    /// 컨트롤을 본다 — 헌법주석처럼 단 정의가 앞서는 저장본도 있어 첫 컨트롤만
    /// 보면 안 된다 (`sectionOutlineNumberingIds`와 같은 조회).
    static func sectionSettings(of file: HwpFile) -> [SectionSettings] {
        file.sectionArray.compactMap { section in
            section.paragraph.first?.ctrlHeaderArray?.lazy.compactMap { ctrl -> SectionSettings? in
                guard case let .section(sectionDef) = ctrl else {
                    return nil
                }
                let property = sectionDef.propertyInfo
                return SectionSettings(
                    pageStartsOn: property.newPageNumberApplyRawValue,
                    pageStartNumber: sectionDef.pageStartNumber,
                    pictureStartNumber: sectionDef.pictureStartNumber,
                    tableStartNumber: sectionDef.tableStartNumber,
                    equationNumber: sectionDef.equationNumber,
                    hidesFirstHeader: property.hideHeader,
                    hidesFirstFooter: property.hideFooter,
                    hidesFirstMasterPage: property.hideMasterPage,
                    hidesFirstPageNumber: property.hidePageNumberPosition
                )
            }.first
        }
    }
}
