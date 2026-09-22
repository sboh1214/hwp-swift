import Foundation

/**
 호환 문서의 대상 프로그램 (표 55, OWPML `hh:compatibleDocument@targetProgram`).

 값과 OWPML 이름은 한컴 공개 모델 `enumdef.h`의 `COMPATIBLEDOCTYPE`
 (`g_CompatiblieDocList`)을 따른다 — 스펙 표 55는 0·1·2만 적고 `Hunmin`(4)은
 한컴 모델에만 있다. 호환 문서 record가 없는 문서는 한글 문서(`hwp201X`)로 다룬다.

 대상 프로그램은 조판·렌더링의 분기 축이다 (#187·#210): 한글은 MS 워드 호환 문서
 (`msWord`)에서 밑줄·취소선·변경 추적 표시선을 글꼴 지표(OS/2 `usWinAscent`·
 `usWinDescent`)로 놓고, 한글 2007 호환 문서(`hwp200X`)에서는 글자 크기 비례 자리에
 **크기와 무관한 고정 0.36pt** 선을 놓으며, 그 밖의 문서에서는 글자 크기 비례 자리에
 0.04em 선을 놓는다 (`HwpKitCore`의 `HwpDecorationLineGeometry`). 레이아웃 호환성
 플래그(표 56)는 이 기하에 관여하지 않는다 (2026-09-15 한글 12.30 실측: 35개 플래그
 전부/없음·개별 `useInnerUnderline`·`useLowercaseStrikeout`이 같은 결과). 훈민정음
 호환(`hunmin`)·record 없음은 한글 문서와 같이 다룬다.
 */
public enum HwpCompatibleDocumentTarget: UInt32, HwpPrimitive, CaseIterable {
    /** 한글 문서(현재 버전) — `HWP201X` */
    case hwp201X = 0
    /** 한글 2007 호환 문서 — `HWP200X` */
    case hwp200X = 1
    /** MS 워드 호환 문서 — `MS_WORD` */
    case msWord = 2
    /** 훈민정음 호환 문서 — `Hunmin` (한컴 모델 `CT_HUNMIN`) */
    case hunmin = 4

    /** OWPML `targetProgram` 속성 이름 (한컴 모델 `g_CompatiblieDocList`) */
    public var owpmlName: String {
        switch self {
        case .hwp201X: "HWP201X"
        case .hwp200X: "HWP200X"
        case .msWord: "MS_WORD"
        case .hunmin: "Hunmin"
        }
    }

    /** OWPML 이름으로 찾는다 — 대소문자까지 한컴 모델 그대로여야 한다. */
    public init?(owpmlName: String) {
        guard let target = Self.allCases.first(where: { $0.owpmlName == owpmlName }) else {
            return nil
        }
        self = target
    }
}

public extension HwpCompatibleDocument {
    /**
     대상 프로그램. 표 55·한컴 모델에 없는 raw 값이면 nil이다 — 소비자는 한글
     문서(`hwp201X`)로 다룬다 (`HwpKitCore`의 `HwpIndex.compatibleDocumentTarget`).
     */
    var target: HwpCompatibleDocumentTarget? {
        HwpCompatibleDocumentTarget(rawValue: targetDocument)
    }
}
