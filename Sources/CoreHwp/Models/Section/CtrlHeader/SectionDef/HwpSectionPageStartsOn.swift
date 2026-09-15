/**
 구역 시작 종류 — 구역 나눔으로 새 쪽이 생길 때 첫 쪽의 쪽 번호를 어느 쪽에 맞출지
 (표 130 구역 정의 속성 bits 20-21, OWPML `STARTNUMSTARTONTYPE`).

 한글 12.30은 홀수·짝수 시작 때문에 빈 쪽을 끼우지 않고 새 구역 첫 쪽의 **번호만**
 건너뛴다 — 앞 구역이 1쪽에서 끝난 뒤 홀수 시작 구역의 첫 쪽은 3쪽이고, 그 사이에
 물리 쪽은 없다. 사용자 지정 시작 번호(`HwpSectionDef.pageStartNumber` > 0)가 있으면
 그 번호를 그대로 쓰고 종류는 보지 않는다 (홀수 + 시작 4 → 4). 값은 한컴 공개 모델
 `enumdef.h`와 같다 — 스펙 표 130은 이 비트의 값을 적지 않는다 (#173).
 */
public enum HwpSectionPageStartsOn: Int, HwpPrimitive {
    /** 앞 구역에 이어서 (`BOTH`) */
    case both = 0
    /** 짝수 쪽에서 시작 (`EVEN`) — 이어지는 번호가 홀수면 1을 건너뛴다 */
    case even = 1
    /** 홀수 쪽에서 시작 (`ODD`) — 이어지는 번호가 짝수면 1을 건너뛴다 */
    case odd = 2
}

public extension HwpSectionDefProperty {
    /**
     구역 시작 종류 (bits 20-21). 정의되지 않은 raw 값 3이면 nil이다 — 소비자는
     이어서(`both`)로 다룬다.
     */
    var pageStartsOn: HwpSectionPageStartsOn? {
        HwpSectionPageStartsOn(rawValue: newPageNumberApplyRawValue)
    }
}

public extension HwpSectionDef {
    /**
     이 구역의 첫 쪽이 받을 논리 쪽 번호. `continuing`은 앞 구역에 이어질 때의 번호
     (문서 첫 구역이면 1)다.

     사용자 지정 시작 번호(`pageStartNumber` > 0)는 그대로 돌려주고 종류를 보지
     않는다. 그 밖에는 ``HwpSectionPageStartsOn``에 따라 홀짝이 어긋난 번호만 1 건너뛴다.
     이미 맞거나 이어서(`both`)면 `continuing` 그대로다. 문서 첫 구역도 같은 규칙이라
     짝수 시작 첫 구역의 첫 쪽은 2다 (한글 12.30 실측).
     */
    func firstPageNumber(continuing: Int) -> Int {
        if pageStartNumber > 0 {
            return Int(pageStartNumber)
        }
        switch propertyInfo.pageStartsOn {
        case .even where !continuing.isMultiple(of: 2):
            return continuing + 1
        case .odd where continuing.isMultiple(of: 2):
            return continuing + 1
        default:
            return continuing
        }
    }
}
